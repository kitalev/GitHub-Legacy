#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Block.h>
#import <dlfcn.h>
#import <pthread.h>

#define GH_ARC_EXPORT __attribute__((visibility("hidden")))

static void * const kGHARCAbsent = (void *)1;

static void *GHARCResolve(void **slot, const char *name) {
    void *fn = *slot;
    if (fn == NULL) {
        fn = dlsym(RTLD_DEFAULT, name);
        if (fn == NULL) fn = kGHARCAbsent;
        *slot = fn;
    }
    return fn == kGHARCAbsent ? NULL : fn;
}

#define GH_NATIVE(type, name) \
    static void *name##_slot; \
    __typeof__(type) name##_native = (type)GHARCResolve(&name##_slot, #name)

@interface GHWeakSentinel : NSObject {
@public
    CFMutableSetRef _slots;
}
@end

static pthread_mutex_t gGHWeakLock = PTHREAD_MUTEX_INITIALIZER;
static char kGHWeakSentinelKey;

@implementation GHWeakSentinel

- (void)dealloc {
    pthread_mutex_lock(&gGHWeakLock);
    if (_slots != NULL) {
        CFIndex count = CFSetGetCount(_slots);
        if (count > 0) {
            const void **values = malloc(sizeof(void *) * count);
            CFSetGetValues(_slots, values);
            for (CFIndex i = 0; i < count; i++) {
                *(id *)values[i] = nil;
            }
            free(values);
        }
        CFRelease(_slots);
        _slots = NULL;
    }
    pthread_mutex_unlock(&gGHWeakLock);
    [super dealloc];
}

@end

static void GHWeakUnregister(id *location, id object) {
    if (object == nil) return;
    GHWeakSentinel *sentinel = objc_getAssociatedObject(object, &kGHWeakSentinelKey);
    if (sentinel != nil && sentinel->_slots != NULL) {
        CFSetRemoveValue(sentinel->_slots, location);
    }
}

static void GHWeakRegister(id *location, id object) {
    GHWeakSentinel *sentinel = objc_getAssociatedObject(object, &kGHWeakSentinelKey);
    if (sentinel == nil) {
        sentinel = [[GHWeakSentinel alloc] init];
        objc_setAssociatedObject(object, &kGHWeakSentinelKey, sentinel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sentinel release];
    }
    if (sentinel->_slots == NULL) {
        sentinel->_slots = CFSetCreateMutable(NULL, 0, NULL);
    }
    CFSetAddValue(sentinel->_slots, location);
}

static id GHWeakStore(id *location, id object) {
    pthread_mutex_lock(&gGHWeakLock);
    id previous = *location;
    if (previous != object) {
        GHWeakUnregister(location, previous);
        if (object != nil) GHWeakRegister(location, object);
        *location = object;
    }
    pthread_mutex_unlock(&gGHWeakLock);
    return object;
}

static id GHWeakLoadRetained(id *location) {
    pthread_mutex_lock(&gGHWeakLock);
    id object = [*location retain];
    pthread_mutex_unlock(&gGHWeakLock);
    return object;
}

GH_ARC_EXPORT id objc_retain(id object) {
    GH_NATIVE(id (*)(id), objc_retain);
    if (objc_retain_native) return objc_retain_native(object);
    return [object retain];
}

GH_ARC_EXPORT void objc_release(id object) {
    GH_NATIVE(void (*)(id), objc_release);
    if (objc_release_native) {
        objc_release_native(object);
        return;
    }
    [object release];
}

GH_ARC_EXPORT id objc_autorelease(id object) {
    GH_NATIVE(id (*)(id), objc_autorelease);
    if (objc_autorelease_native) return objc_autorelease_native(object);
    return [object autorelease];
}

GH_ARC_EXPORT id objc_retainAutorelease(id object) {
    GH_NATIVE(id (*)(id), objc_retainAutorelease);
    if (objc_retainAutorelease_native) return objc_retainAutorelease_native(object);
    return [[object retain] autorelease];
}

GH_ARC_EXPORT id objc_autoreleaseReturnValue(id object) {
    GH_NATIVE(id (*)(id), objc_autoreleaseReturnValue);
    if (objc_autoreleaseReturnValue_native) return objc_autoreleaseReturnValue_native(object);
    return [object autorelease];
}

GH_ARC_EXPORT id objc_retainAutoreleaseReturnValue(id object) {
    GH_NATIVE(id (*)(id), objc_retainAutoreleaseReturnValue);
    if (objc_retainAutoreleaseReturnValue_native) return objc_retainAutoreleaseReturnValue_native(object);
    return [[object retain] autorelease];
}

GH_ARC_EXPORT id objc_retainAutoreleasedReturnValue(id object) {
    GH_NATIVE(id (*)(id), objc_retainAutoreleasedReturnValue);
    if (objc_retainAutoreleasedReturnValue_native) return objc_retainAutoreleasedReturnValue_native(object);
    return [object retain];
}

GH_ARC_EXPORT id objc_retainBlock(id block) {
    GH_NATIVE(id (*)(id), objc_retainBlock);
    if (objc_retainBlock_native) return objc_retainBlock_native(block);
    return (id)_Block_copy(block);
}

GH_ARC_EXPORT void objc_storeStrong(id *location, id object) {
    GH_NATIVE(void (*)(id *, id), objc_storeStrong);
    if (objc_storeStrong_native) {
        objc_storeStrong_native(location, object);
        return;
    }
    id previous = *location;
    if (previous == object) return;
    *location = [object retain];
    [previous release];
}

GH_ARC_EXPORT void *objc_autoreleasePoolPush(void) {
    GH_NATIVE(void *(*)(void), objc_autoreleasePoolPush);
    if (objc_autoreleasePoolPush_native) return objc_autoreleasePoolPush_native();
    return [[NSAutoreleasePool alloc] init];
}

GH_ARC_EXPORT void objc_autoreleasePoolPop(void *pool) {
    GH_NATIVE(void (*)(void *), objc_autoreleasePoolPop);
    if (objc_autoreleasePoolPop_native) {
        objc_autoreleasePoolPop_native(pool);
        return;
    }
    [(NSAutoreleasePool *)pool drain];
}

GH_ARC_EXPORT id GHARCStoreWeak(id *location, id object) __asm__("_objc_storeWeak");

GH_ARC_EXPORT id GHARCStoreWeak(id *location, id object) {
    GH_NATIVE(id (*)(id *, id), objc_storeWeak);
    if (objc_storeWeak_native) return objc_storeWeak_native(location, object);
    return GHWeakStore(location, object);
}

GH_ARC_EXPORT id objc_initWeak(id *location, id object) {
    GH_NATIVE(id (*)(id *, id), objc_initWeak);
    if (objc_initWeak_native) return objc_initWeak_native(location, object);
    *location = nil;
    return GHWeakStore(location, object);
}

GH_ARC_EXPORT void objc_destroyWeak(id *location) {
    GH_NATIVE(void (*)(id *), objc_destroyWeak);
    if (objc_destroyWeak_native) {
        objc_destroyWeak_native(location);
        return;
    }
    GHWeakStore(location, nil);
}

GH_ARC_EXPORT id objc_loadWeakRetained(id *location) {
    GH_NATIVE(id (*)(id *), objc_loadWeakRetained);
    if (objc_loadWeakRetained_native) return objc_loadWeakRetained_native(location);
    return GHWeakLoadRetained(location);
}

GH_ARC_EXPORT id GHARCLoadWeak(id *location) __asm__("_objc_loadWeak");

GH_ARC_EXPORT id GHARCLoadWeak(id *location) {
    GH_NATIVE(id (*)(id *), objc_loadWeak);
    if (objc_loadWeak_native) return objc_loadWeak_native(location);
    return [GHWeakLoadRetained(location) autorelease];
}

GH_ARC_EXPORT void objc_copyWeak(id *to, id *from) {
    GH_NATIVE(void (*)(id *, id *), objc_copyWeak);
    if (objc_copyWeak_native) {
        objc_copyWeak_native(to, from);
        return;
    }
    id object = GHWeakLoadRetained(from);
    *to = nil;
    GHWeakStore(to, object);
    [object release];
}

GH_ARC_EXPORT void objc_moveWeak(id *to, id *from) {
    GH_NATIVE(void (*)(id *, id *), objc_moveWeak);
    if (objc_moveWeak_native) {
        objc_moveWeak_native(to, from);
        return;
    }
    id object = GHWeakLoadRetained(from);
    *to = nil;
    GHWeakStore(to, object);
    GHWeakStore(from, nil);
    [object release];
}
