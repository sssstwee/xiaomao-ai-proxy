#pragma once

#include <stdbool.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

extern void (*release_object_func)(void *object);
extern void (*free_string_func)(char *data);
extern bool (*protect_func)(void *handler, int fd);
extern int (*resolve_uid_func)(void *handler, int protocol, const char *source, const char *target);
extern char *(*resolve_package_func)(void *handler, int uid);
extern void (*result_func)(void *handler, const char *data);

extern void release_object(void *object);
extern void free_string(char *data);
extern bool protect(void *handler, int fd);
extern int resolve_uid(void *handler, int protocol, const char *source, const char *target);
extern char *resolve_package(void *handler, int uid);
extern void result(void *handler, const char *data);

#ifdef __cplusplus
}
#endif
