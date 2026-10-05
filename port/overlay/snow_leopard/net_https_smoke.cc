// Exercise Chromium 124's real URLRequest/BoringSSL/trust-store path on 10.6.
#include <stdio.h>

#include <memory>
#include <string>

#include "base/apple/scoped_nsautorelease_pool.h"
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/i18n/icu_util.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/thread_pool/thread_pool_instance.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "net/base/io_buffer.h"
#include "net/base/net_errors.h"
#include "net/base/network_change_notifier.h"
#include "net/ssl/ssl_info.h"
#include "net/cookies/cookie_store.h"
#include "net/traffic_annotation/network_traffic_annotation_test_helper.h"
#include "net/url_request/url_request.h"
#include "net/url_request/url_request_context.h"
#include "net/url_request/url_request_context_builder.h"
#include "url/gurl.h"

namespace {
class Fetch final : public net::URLRequest::Delegate {
 public:
  explicit Fetch(net::URLRequestContext* context) : context_(context) {}

  bool Run(const char* url, bool expect_certificate_failure) {
    request_ = context_->CreateRequest(GURL(url), net::DEFAULT_PRIORITY, this,
                                      TRAFFIC_ANNOTATION_FOR_TESTS);
    timeout_.Start(FROM_HERE, base::Seconds(30),
                   base::BindOnce(&Fetch::Timeout, base::Unretained(this)));
    request_->Start();
    loop_.Run();
    bool passed = expect_certificate_failure
        ? saw_certificate_error_ && net::IsCertificateError(result_) && bytes_ == 0
        : result_ == net::OK && response_code_ == 200 && bytes_ > 0 &&
              !saw_certificate_error_ && request_->ssl_info().is_valid() &&
              request_->ssl_info().cert_status == 0;
    printf("%s %s: url=%s error=%s http=%d body_bytes=%zu cert_status=%u\n",
           passed ? "PASS" : "FAIL",
           expect_certificate_failure ? "reject invalid HTTPS certificate"
                                      : "verified HTTPS response",
           url, net::ErrorToShortString(result_).c_str(), response_code_, bytes_,
           request_->ssl_info().cert_status);
    request_.reset();
    return passed;
  }

  void OnSSLCertificateError(net::URLRequest* request, int error,
                             const net::SSLInfo& ssl_info, bool fatal) override {
    saw_certificate_error_ = true;
    // This test must never continue a request after a certificate error.
    request->CancelWithError(error);
    Finish(error);
  }

  void OnResponseStarted(net::URLRequest* request, int error) override {
    if (error != net::OK) {
      Finish(error);
      return;
    }
    response_code_ = request->GetResponseCode();
    Read();
  }

  void OnReadCompleted(net::URLRequest* request, int bytes_read) override {
    if (bytes_read <= 0) {
      Finish(bytes_read);
      return;
    }
    bytes_ += static_cast<size_t>(bytes_read);
    Read();
  }

 private:
  void Read() {
    while (!finished_) {
      int result = request_->Read(buffer_.get(), buffer_->size());
      if (result == net::ERR_IO_PENDING)
        return;
      if (result <= 0) {
        Finish(result);
        return;
      }
      bytes_ += static_cast<size_t>(result);
      if (bytes_ > 1024 * 1024) {
        request_->CancelWithError(net::ERR_FILE_TOO_BIG);
        Finish(net::ERR_FILE_TOO_BIG);
      }
    }
  }

  void Timeout() {
    request_->CancelWithError(net::ERR_TIMED_OUT);
    Finish(net::ERR_TIMED_OUT);
  }

  void Finish(int error) {
    if (finished_)
      return;
    finished_ = true;
    result_ = error;
    timeout_.Stop();
    loop_.Quit();
  }

  net::URLRequestContext* context_;
  base::RunLoop loop_;
  base::OneShotTimer timeout_;
  scoped_refptr<net::IOBufferWithSize> buffer_ =
      base::MakeRefCounted<net::IOBufferWithSize>(16 * 1024);
  std::unique_ptr<net::URLRequest> request_;
  bool finished_ = false;
  bool saw_certificate_error_ = false;
  int result_ = net::ERR_UNEXPECTED;
  int response_code_ = 0;
  size_t bytes_ = 0;
};
}  // namespace

int main(int argc, char** argv) {
  setbuf(stdout, nullptr);
  base::apple::ScopedNSAutoreleasePool autorelease_pool;
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::FeatureList::InitInstance("", "");
  if (!base::i18n::InitializeICU()) {
    fprintf(stderr, "FAIL ICU data initialization (place icudtl.dat beside executable)\n");
    return 1;
  }
  base::SingleThreadTaskExecutor io_executor(base::MessagePumpType::IO);
  base::ThreadPoolInstance::CreateAndStartWithDefaultParams("SnowiumHTTPS");
  bool passed;
  {
    auto network_notifier = net::NetworkChangeNotifier::CreateIfNeeded();
    net::URLRequestContextBuilder builder;
    builder.DisableHttpCache();
    builder.SetCookieStore(nullptr);
    builder.set_user_agent("Snowium-124-native-test");
    auto context = builder.Build();
    Fetch valid(context.get());
    bool valid_ok = valid.Run(argc > 1 ? argv[1] : "https://example.com/", false);
    Fetch invalid(context.get());
    bool invalid_ok = invalid.Run(argc > 2 ? argv[2] : "https://expired.badssl.com/", true);
    passed = valid_ok && invalid_ok;
  }
  base::ThreadPoolInstance::Get()->Shutdown();
  return passed ? 0 : 1;
}
