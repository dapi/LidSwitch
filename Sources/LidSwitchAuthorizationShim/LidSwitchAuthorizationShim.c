#include "LidSwitchAuthorizationShim.h"

OSStatus LidSwitchExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *executablePath,
    char *const *arguments,
    FILE **communicationsPipe
) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = AuthorizationExecuteWithPrivileges(
        authorization,
        executablePath,
        kAuthorizationFlagDefaults,
        arguments,
        communicationsPipe
    );
#pragma clang diagnostic pop
    return status;
}
