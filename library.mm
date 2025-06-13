#include "library.h"
#import <FlutterEmbedder/FlutterEmbedder.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <IOSurface/IOSurface.h>
#import "com_syeyoung_fluttermc_FlutterGuiScreen.h"
#import "rapidjson/document.h"
#import "rapidjson/stringbuffer.h"
#import "rapidjson/writer.h"
#include <iostream>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <future>


// This value is calculated after the window is created.
static const size_t kInitialWindowWidth = 800;
static const size_t kInitialWindowHeight = 600;
static constexpr FlutterViewId kImplicitViewId = 0;

static_assert(FLUTTER_ENGINE_VERSION == 1,
              "This Flutter Embedder was authored against the stable Flutter "
              "API at version 1. There has been a serious breakage in the "
              "API. Please read the ChangeLog and take appropriate action "
              "before updating this assertion");
//
//void GLFWcursorPositionCallbackAtPhase(GLFWwindow* window,
//                                       FlutterPointerPhase phase,
//                                       double x,
//                                       double y) {
//}
//
//void GLFWcursorPositionCallback(GLFWwindow* window, double x, double y) {
//    GLFWcursorPositionCallbackAtPhase(window, FlutterPointerPhase::kMove, x, y);
//}
//
//void GLFWmouseButtonCallback(GLFWwindow* window,
//                             int key,
//                             int action,
//                             int mods) {
//    if (key == GLFW_MOUSE_BUTTON_1 && action == GLFW_PRESS) {
//        double x, y;
//        glfwGetCursorPos(window, &x, &y);
//        GLFWcursorPositionCallbackAtPhase(window, FlutterPointerPhase::kDown, x, y);
//        glfwSetCursorPosCallback(window, GLFWcursorPositionCallback);
//    }
//
//    if (key == GLFW_MOUSE_BUTTON_1 && action == GLFW_RELEASE) {
//        double x, y;
//        glfwGetCursorPos(window, &x, &y);
//        GLFWcursorPositionCallbackAtPhase(window, FlutterPointerPhase::kUp, x, y);
//        glfwSetCursorPosCallback(window, nullptr);
//    }
//}
//
//static void GLFWKeyCallback(GLFWwindow* window,
//                            int key,
//                            int scancode,
//                            int action,
//                            int mods) {
//    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
//        glfwSetWindowShouldClose(window, GLFW_TRUE);
//    }
//}
//
//void GLFWwindowSizeCallback(GLFWwindow* window, int width, int height) {
//    FlutterWindowMetricsEvent event = {};
//    event.struct_size = sizeof(event);
//    event.width = width * g_pixelRatio;
//    event.height = height * g_pixelRatio;
//    event.pixel_ratio = g_pixelRatio;
//    // This example only supports a single window, therefore we assume the event
//    // occurred in the only view, the implicit view.
//    event.view_id = kImplicitViewId;
//    FlutterEngineSendWindowMetricsEvent(
//            reinterpret_cast<FlutterEngine>(glfwGetWindowUserPointer(window)),
//            &event);
//}

struct FlutterRunContext {
    id<MTLTexture> metalTexture;
    FlutterMetalTexture texture = {
            .texture_id = -1
    };
    FlutterEngine engine;
    IOSurfaceRef ioSurface;
    id<MTLDevice> device;
    GLuint textureId = -1;
};

void OnFlutterPlatformMessage(const FlutterPlatformMessage* message, void* handle) {
    FlutterRunContext* context = reinterpret_cast<FlutterRunContext *>(handle);

    std::cout << message->channel << " Says: ";
    std::string str(reinterpret_cast<const char*>(message->message), message->message_size);
    std::cout << str << "\n" << std::flush;

    uint8 a = 0;
    FlutterEngineSendPlatformMessageResponse(context->engine, message->response_handle, &a, 0);
};

FlutterRunContext* RunFlutter(const std::string& project_path,
                const std::string& icudtl_path) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> queue = [device newCommandQueue];


    // Define IOSurface properties
    NSDictionary *surfaceAttributes = @{
            (NSString *)kIOSurfaceWidth: @(kInitialWindowWidth),
            (NSString *)kIOSurfaceHeight: @(kInitialWindowHeight),
            (NSString *)kIOSurfaceBytesPerElement: @4, // e.g. BGRA8 = 4 bytes/pixel
            (NSString *)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
    };

    // Create IOSurface
    IOSurfaceRef ioSurface = IOSurfaceCreate((CFDictionaryRef)surfaceAttributes);
    // Create Metal texture from IOSurface



    FlutterRendererConfig config = {};
    config.type = kMetal;
    config.metal.device = device;
    config.metal.present_command_queue = queue;
    config.metal.struct_size = sizeof(config.metal);
    config.metal.get_next_drawable_callback = [](void* a, const FlutterFrameInfo* b) {
        FlutterRunContext* runContext = static_cast<FlutterRunContext *>(a);
        if (runContext->texture.texture_id != -1) {
            return runContext->texture;
        }

        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                        width:IOSurfaceGetWidth(runContext->ioSurface)
                                                                                       height:IOSurfaceGetHeight(runContext->ioSurface)
                                                                                    mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        desc.storageMode = MTLStorageModeShared;
        id<MTLTexture> metalTexture = [runContext->device newTextureWithDescriptor:desc
                                                             iosurface:runContext->ioSurface
                                                                 plane:0];

        FlutterMetalTexture texture;
        texture.struct_size = sizeof(texture);
        texture.texture = metalTexture;
        texture.texture_id = 0;
        runContext->texture = texture;
        return texture;
    };
    config.metal.present_drawable_callback = [](auto a, const FlutterMetalTexture* b) {
        return true;
    };
    config.metal.external_texture_frame_callback = [](void* a/* user data */,
                                                      int64_t b/* texture identifier */,
                                                      size_t c/* width */,
                                                      size_t d/* height */,
                                                      FlutterMetalExternalTexture* e) {
        return false;
    };

    // This directory is generated by `flutter build bundle`.
    std::string assets_path = project_path + "/build/flutter_assets";
    FlutterProjectArgs args = {
            .struct_size = sizeof(FlutterProjectArgs),
            .assets_path = assets_path.c_str(),
            .icu_data_path = icudtl_path.c_str(),
            .platform_message_callback = OnFlutterPlatformMessage,
            .log_message_callback = [](const char *tag, const char *message, void* user_data) {
                std::cout << tag << message << "\n"  << std::flush;
            }
            // Find this in your bin/cache directory.
    };
    FlutterEngine engine = nullptr;

    auto* runContext = new FlutterRunContext();
    runContext->ioSurface=ioSurface;
    runContext->device = device;

    FlutterEngineResult result = FlutterEngineInitialize(FLUTTER_ENGINE_VERSION, &config,  // renderer
                             &args, runContext, &engine);
    if (result != kSuccess || engine == nullptr) {
        std::cout << "Could not run the Flutter Engine." << std::endl;
        delete runContext;
        return NULL;
    }
    runContext -> engine = engine;
    FlutterEngineRunInitialized(engine);
    if (result != kSuccess || engine == nullptr) {
        std::cout << "Could not run the Flutter Engine." << std::endl;
        delete runContext;
        return NULL;
    }
    std::cout << "HMM"<<std::endl;


    return runContext;
}

std::string JStringToString(JNIEnv* env, jstring jStr) {
    if (!jStr) return "";

    const char* chars = env->GetStringUTFChars(jStr, nullptr);
    std::string str(chars);
    env->ReleaseStringUTFChars(jStr, chars);

    return str;
}


JNIEXPORT jlong JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_startFlutter
        (JNIEnv *env, jclass, jstring _project_path, jstring _icudtl_path) {
    std::string project_path = JStringToString(env, _project_path);
    std::string icudtl_path = JStringToString(env, _icudtl_path);

    FlutterRunContext* run_result = RunFlutter(project_path, icudtl_path);
    if (!run_result) {
        std::cout << "Could not run the Flutter engine." << std::endl;
        return 0;
    }

    FlutterWindowMetricsEvent event = {};
    event.struct_size = sizeof(event);
    event.width = kInitialWindowWidth;
    event.height = kInitialWindowHeight;
    event.pixel_ratio = 1;
    event.view_id = kImplicitViewId;

    FlutterEngineSendWindowMetricsEvent(run_result->engine, &event);
    return (jlong) (run_result);
}

/*
 * Class:     com_syeyoung_fluttermc_FlutterGuiScreen
 * Method:    bindTexture
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_bindTexture
        (JNIEnv *, jclass, jlong handle, jlong textureId) {
    FlutterRunContext* context = reinterpret_cast<FlutterRunContext *>(handle);
    context->textureId = textureId;
    glBindTexture(GL_TEXTURE_RECTANGLE_EXT, textureId);
//
    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // Bind IOSurface to GL texture
    CGLContextObj cglContext = CGLGetCurrentContext();
    CGLTexImageIOSurface2D(cglContext,
                           GL_TEXTURE_RECTANGLE_EXT,
                           GL_RGBA, IOSurfaceGetWidth(context->ioSurface), IOSurfaceGetHeight(context->ioSurface),
                           GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV,
                           context->ioSurface, 0);
}

/*
 * Class:     com_syeyoung_fluttermc_FlutterGuiScreen
 * Method:    resize
 * Signature: (JII)V
 */
JNIEXPORT void JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_resize
        (JNIEnv *, jclass, jlong handle, jint width, jint height) {

    FlutterWindowMetricsEvent event = {};
    event.struct_size = sizeof(event);
    event.width = width;
    event.height = height;
    event.pixel_ratio = 1;
    event.view_id = kImplicitViewId;

    FlutterRunContext* context = reinterpret_cast<FlutterRunContext *>(handle);

    // Define IOSurface properties
    NSDictionary *surfaceAttributes = @{
            (NSString *)kIOSurfaceWidth: @(width),
            (NSString *)kIOSurfaceHeight: @(height),
            (NSString *)kIOSurfaceBytesPerElement: @4, // e.g. BGRA8 = 4 bytes/pixel
            (NSString *)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
    };

    // Create IOSurface
    IOSurfaceRef ioSurface = IOSurfaceCreate((CFDictionaryRef)surfaceAttributes);
    CFRelease(context->ioSurface);
    context->ioSurface = ioSurface;

    if (context->texture.texture_id != -1) {
        context->texture.texture_id = -1;
        [context->metalTexture release];
    }

    if (context->textureId != -1) {
        glBindTexture(GL_TEXTURE_RECTANGLE_EXT, context->textureId);
//
        glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        // Bind IOSurface to GL texture
        CGLContextObj cglContext = CGLGetCurrentContext();
        CGLTexImageIOSurface2D(cglContext,
                               GL_TEXTURE_RECTANGLE_EXT,
                               GL_RGBA, IOSurfaceGetWidth(context->ioSurface), IOSurfaceGetHeight(context->ioSurface),
                               GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV,
                               context->ioSurface, 0);
    }

    FlutterEngineSendWindowMetricsEvent(context->engine, &event);

}
JNIEXPORT void JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_scrollEvent
        (JNIEnv *, jclass, jlong handle, jint x, jint y, jint scroll) {
    FlutterRunContext* context = reinterpret_cast<FlutterRunContext *>(handle);

    FlutterPointerEvent event = {};
    event.struct_size = sizeof(event);
    event.x = x;
    event.y = y;
    event.scroll_delta_y = scroll;
    event.signal_kind = kFlutterPointerSignalKindScroll;
    event.timestamp =
            std::chrono::duration_cast<std::chrono::microseconds>(
                    std::chrono::high_resolution_clock::now().time_since_epoch())
                    .count();
    // This example only supports a single window, therefore we assume the pointer
    // event occurred in the only view, the implicit view.
    event.view_id = kImplicitViewId;
    FlutterEngineSendPointerEvent(context->engine, &event, 1);
}

JNIEXPORT void JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_mouseEvent
        (JNIEnv *, jclass, jlong handle, jint type, jint x, jint y, jint button) {
    FlutterRunContext* context = reinterpret_cast<FlutterRunContext *>(handle);

    FlutterPointerEvent event = {};
    event.struct_size = sizeof(event);
    event.phase = static_cast<FlutterPointerPhase>(type);
    event.x = x;
    event.y = y;
    event.buttons = button;
    event.timestamp =
            std::chrono::duration_cast<std::chrono::microseconds>(
                    std::chrono::high_resolution_clock::now().time_since_epoch())
                    .count();
    // This example only supports a single window, therefore we assume the pointer
    // event occurred in the only view, the implicit view.
    event.view_id = kImplicitViewId;
    FlutterEngineSendPointerEvent(context->engine, &event, 1);
}


static constexpr char kChannelName[] = "flutter/keyevent";

static constexpr char kKeyCodeKey[] = "keyCode";
static constexpr char kKeyMapKey[] = "keymap";
static constexpr char kScanCodeKey[] = "scanCode";
static constexpr char kModifiersKey[] = "modifiers";
static constexpr char kTypeKey[] = "type";
static constexpr char kToolkitKey[] = "toolkit";
static constexpr char kUnicodeScalarValues[] = "unicodeScalarValues";

static constexpr char kLinuxKeyMap[] = "linux";
static constexpr char kGLFWKey[] = "glfw";

static constexpr char kKeyUp[] = "keyup";
static constexpr char kKeyDown[] = "keydown";

JNIEXPORT jboolean JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_keyEvent
        (JNIEnv *, jclass, jlong handle, jint type, jint key, jint mods, jchar ch) {
    FlutterRunContext* context = reinterpret_cast<FlutterRunContext *>(handle);

    rapidjson::Document event(rapidjson::kObjectType);
    auto& allocator = event.GetAllocator();
    event.AddMember(kKeyCodeKey, key, allocator);
    event.AddMember(kKeyMapKey, kLinuxKeyMap, allocator);
    event.AddMember(kScanCodeKey, key, allocator);
    event.AddMember(kModifiersKey, mods, allocator);
    event.AddMember(kToolkitKey, kGLFWKey, allocator);
    event.AddMember(kUnicodeScalarValues, ch, allocator);

    switch (type) {
        case 0:
        case 1:
            event.AddMember(kTypeKey, kKeyDown, allocator);
            break;
        case 2:
            event.AddMember(kTypeKey, kKeyUp, allocator);
            break;
        default:
            std::cerr << "Unknown key event action: " << type << std::endl;
            return false;
    }

    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    event.Accept(writer);

    std::string jsonStr = buffer.GetString();
    const auto* bytePtr = reinterpret_cast<const uint8_t*>(jsonStr.data());
    FlutterPlatformMessageResponseHandle* response_handle;

    auto respPtr = std::make_shared<std::promise<bool>>();
    std::future<bool> future = respPtr->get_future();
    FlutterPlatformMessageCreateResponseHandle(context->engine, [](const uint8_t* data,
                                                                   size_t size,
                                                                   void* user_data) {
        auto resp = static_cast<std::shared_ptr<std::promise<bool>>*>(user_data);

        std::cout <<" RESP:  " << size << " ";
        std::string str(reinterpret_cast<const char*>(data),size);
        std::cout << str << "\n" << std::flush;

        (*resp)->set_value(false);
        delete resp;
    }, new std::shared_ptr<std::promise<bool>>(respPtr), &response_handle);

    FlutterPlatformMessage message = {};
    message.channel = kChannelName;
    message.struct_size = sizeof(message);
    message.message = bytePtr;
    message.message_size = jsonStr.size();
    message.response_handle = response_handle;
    FlutterEngineResult  result = FlutterEngineSendPlatformMessage(context->engine, &message);
    std::cout << "RESULT: " << result << "\n" << std::flush;

    while (future.wait_for(std::chrono::milliseconds(0)) != std::future_status::ready) {
        __FlutterEngineFlushPendingTasksNow();
    }
    auto val = future.get();
    FlutterPlatformMessageReleaseResponseHandle(context->engine, response_handle);
    return val;
}

JNIEXPORT void JNICALL Java_com_syeyoung_fluttermc_FlutterGuiScreen_runTasks
        (JNIEnv *, jclass, jlong handle) {
    __FlutterEngineFlushPendingTasksNow();
}