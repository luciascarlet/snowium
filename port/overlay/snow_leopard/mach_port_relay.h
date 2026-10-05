// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// Adapted from Chromium 60's base/mac/mach_port_util and mojo MachPortRelay.

#ifndef SNOW_LEOPARD_MACH_PORT_RELAY_H_
#define SNOW_LEOPARD_MACH_PORT_RELAY_H_

#include <mach/mach.h>

namespace snow_leopard {

// The caller is a broker holding a task right supplied by its own child.
// Copies a send right into a one-message receive port allocated in that child.
// On success the child owns *remote_receive and must consume and destroy it.
// |send_right| remains owned by the caller on both success and failure.
kern_return_t CreateIntermediateMachPort(mach_port_t child_task,
                                         mach_port_t send_right,
                                         mach_port_name_t* remote_receive);

// Receives the copied send right from a broker-created intermediate port.
// The caller owns the intermediate receive right and must destroy it afterward.
// On success the caller owns *send_right. This call never waits for a message.
kern_return_t ReceiveIntermediateMachPort(mach_port_t receive_right,
                                          mach_port_t* send_right);

// Moves a send right from a child task into the broker's namespace. The child
// relinquishes its user reference only when extraction succeeds.
kern_return_t ExtractMachSendRight(mach_port_t child_task,
                                   mach_port_name_t remote_name,
                                   mach_port_t* send_right);

}  // namespace snow_leopard

#endif
