//go:build openharmony && cgo

#include "bridge.h"

void (*release_object_func)(void *object) = NULL;
void (*free_string_func)(char *data) = NULL;
bool (*protect_func)(void *handler, int fd) = NULL;
int (*resolve_uid_func)(void *handler, int protocol, const char *source, const char *target) = NULL;
char *(*resolve_package_func)(void *handler, int uid) = NULL;
void (*result_func)(void *handler, const char *data) = NULL;

void release_object(void *object) {
    if (object != NULL && release_object_func != NULL) release_object_func(object);
}

void free_string(char *data) {
    if (free_string_func != NULL) free_string_func(data);
    else free(data);
}

bool protect(void *handler, int fd) {
    return protect_func != NULL && protect_func(handler, fd);
}

int resolve_uid(void *handler, int protocol, const char *source, const char *target) {
    return resolve_uid_func == NULL ? -1 : resolve_uid_func(handler, protocol, source, target);
}

char *resolve_package(void *handler, int uid) {
    return resolve_package_func == NULL ? NULL : resolve_package_func(handler, uid);
}

void result(void *handler, const char *data) {
    if (result_func != NULL) result_func(handler, data);
}
