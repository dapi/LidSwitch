#pragma once

#include <Security/Authorization.h>
#include <stdio.h>

OSStatus LidSwitchExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *executablePath,
    char *const *arguments,
    FILE **communicationsPipe
);
