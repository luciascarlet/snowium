// Read-only certificate enumeration for the Darwin 10 keychain API.
#ifndef SNOW_LEOPARD_SECURITY_COMPAT_H_
#define SNOW_LEOPARD_SECURITY_COMPAT_H_

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

// keychains is NULL (the user's normal search list), one SecKeychainRef, or
// an array of keychains. On success, *result owns an array of certificate refs.
// Return an actual error instead of accepting a partial enumeration.
static inline OSStatus SnowiumCopyKeychainCertificates(CFTypeRef keychains,
                                                       CFTypeRef* result) {
  *result = NULL;
  SecKeychainSearchRef search = NULL;
  OSStatus status = SecKeychainSearchCreateFromAttributes(
      keychains, kSecCertificateItemClass, NULL, &search);
  if (status != noErr)
    return status;
  CFMutableArrayRef certificates =
      CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
  if (!certificates) {
    CFRelease(search);
    return errSecAllocate;
  }
  while (true) {
    SecKeychainItemRef item = NULL;
    status = SecKeychainSearchCopyNext(search, &item);
    if (status != noErr)
      break;
    CFArrayAppendValue(certificates, item);
    CFRelease(item);
  }
  CFRelease(search);
  if (status != errSecItemNotFound) {
    CFRelease(certificates);
    return status;
  }
  if (CFArrayGetCount(certificates) == 0) {
    CFRelease(certificates);
    return errSecItemNotFound;
  }
  *result = certificates;
  return noErr;
}

#endif
