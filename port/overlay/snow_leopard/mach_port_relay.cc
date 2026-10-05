// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// Adapted from Chromium 60's base/mac/mach_port_util and mojo MachPortRelay.

#include "mach_port_relay.h"

#include <cstring>

namespace snow_leopard {
namespace {

struct PortMessage {
  mach_msg_header_t header;
  mach_msg_body_t body;
  mach_msg_port_descriptor_t port;
};

struct ReceivedPortMessage {
  PortMessage message;
  mach_msg_max_trailer_t trailer;
};

const mach_msg_id_t kRelayMessageId = 0x534c5052;  // SLPR

}  // namespace

kern_return_t CreateIntermediateMachPort(mach_port_t child_task,
                                         mach_port_t send_right,
                                         mach_port_name_t* remote_receive) {
  *remote_receive = MACH_PORT_NULL;
  mach_port_name_t endpoint = MACH_PORT_NULL;
  kern_return_t kr = mach_port_allocate(child_task, MACH_PORT_RIGHT_RECEIVE,
                                       &endpoint);
  if (kr != KERN_SUCCESS) return kr;

  mach_port_limits_t limits = {};
  limits.mpl_qlimit = 1;
  kr = mach_port_set_attributes(child_task, endpoint, MACH_PORT_LIMITS_INFO,
                               reinterpret_cast<mach_port_info_t>(&limits),
                               MACH_PORT_LIMITS_INFO_COUNT);
  if (kr != KERN_SUCCESS) {
    mach_port_mod_refs(child_task, endpoint, MACH_PORT_RIGHT_RECEIVE, -1);
    return kr;
  }

  mach_port_t send_once = MACH_PORT_NULL;
  mach_msg_type_name_t type = 0;
  kr = mach_port_extract_right(child_task, endpoint,
                              MACH_MSG_TYPE_MAKE_SEND_ONCE, &send_once, &type);
  if (kr != KERN_SUCCESS) {
    mach_port_mod_refs(child_task, endpoint, MACH_PORT_RIGHT_RECEIVE, -1);
    return kr;
  }

  PortMessage message = {};
  message.header.msgh_bits =
      MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0) | MACH_MSGH_BITS_COMPLEX;
  message.header.msgh_size = sizeof(message);
  message.header.msgh_remote_port = send_once;
  message.header.msgh_id = kRelayMessageId;
  message.body.msgh_descriptor_count = 1;
  message.port.name = send_right;
  message.port.disposition = MACH_MSG_TYPE_COPY_SEND;
  message.port.type = MACH_MSG_PORT_DESCRIPTOR;
  kr = mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                sizeof(message), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
  if (kr != KERN_SUCCESS) {
    // A failed send retains the send-once right and the COPY_SEND source.
    mach_port_deallocate(mach_task_self(), send_once);
    mach_port_mod_refs(child_task, endpoint, MACH_PORT_RIGHT_RECEIVE, -1);
    return kr;
  }
  *remote_receive = endpoint;
  return KERN_SUCCESS;
}

kern_return_t ReceiveIntermediateMachPort(mach_port_t receive_right,
                                          mach_port_t* send_right) {
  *send_right = MACH_PORT_NULL;
  ReceivedPortMessage received = {};
  PortMessage& message = received.message;
  kern_return_t kr = mach_msg(&message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                             0, sizeof(received), receive_right, 0,
                             MACH_PORT_NULL);
  if (kr != KERN_SUCCESS) return kr;
  if (message.header.msgh_id != kRelayMessageId ||
      message.header.msgh_size != sizeof(PortMessage) ||
      !(message.header.msgh_bits & MACH_MSGH_BITS_COMPLEX) ||
      message.body.msgh_descriptor_count != 1 ||
      message.port.type != MACH_MSG_PORT_DESCRIPTOR ||
      message.port.disposition != MACH_MSG_TYPE_PORT_SEND) {
    mach_msg_destroy(&message.header);
    return KERN_INVALID_ARGUMENT;
  }
  *send_right = message.port.name;
  return KERN_SUCCESS;
}

kern_return_t ExtractMachSendRight(mach_port_t child_task,
                                   mach_port_name_t remote_name,
                                   mach_port_t* send_right) {
  *send_right = MACH_PORT_NULL;
  mach_msg_type_name_t type = 0;
  kern_return_t kr = mach_port_extract_right(child_task, remote_name,
                                           MACH_MSG_TYPE_MOVE_SEND,
                                           send_right, &type);
  if (kr != KERN_SUCCESS) return kr;
  if (type != MACH_MSG_TYPE_PORT_SEND) {
    mach_port_deallocate(mach_task_self(), *send_right);
    *send_right = MACH_PORT_NULL;
    return KERN_INVALID_RIGHT;
  }
  return KERN_SUCCESS;
}

}  // namespace snow_leopard
