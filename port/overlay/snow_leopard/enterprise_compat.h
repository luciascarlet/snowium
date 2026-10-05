// Directory Service domain membership on Snow Leopard.
#ifndef SNOW_LEOPARD_ENTERPRISE_COMPAT_H_
#define SNOW_LEOPARD_ENTERPRISE_COMPAT_H_

#import <OpenDirectory/OpenDirectory.h>

// Use the record's actual directory node. The LDAP distinguished-name metadata
// and Foundation's regular-expression search option were added after 10.6.
static inline bool SnowiumIsDomainDirectoryNode(NSString* node) {
  return [node isEqualToString:@"/LDAPv3"] ||
         [node hasPrefix:@"/LDAPv3/"] ||
         [node isEqualToString:@"/Active Directory"] ||
         [node hasPrefix:@"/Active Directory/"];
}

static inline bool SnowiumUserRecordIsDomainJoined(ODRecord* record) {
  NSArray* locations =
      [record valuesForAttribute:kODAttributeTypeMetaNodeLocation error:nil];
  for (id location in locations) {
    if ([location isKindOfClass:[NSString class]] &&
        SnowiumIsDomainDirectoryNode(location)) {
      return true;
    }
  }
  return false;
}

#endif  // SNOW_LEOPARD_ENTERPRISE_COMPAT_H_
