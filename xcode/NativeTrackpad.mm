#include <Core/CoreAll.h>
#include <Fusion/FusionAll.h>
#include <Cam/CAMAll.h>

#include <Foundation/Foundation.h>
#include <Cocoa/Cocoa.h>

#import <objc/runtime.h>

using namespace adsk::core;
using namespace adsk::fusion;
using namespace adsk::cam;

adsk::core::Ptr<Application> app;
adsk::core::Ptr<UserInterface> ui;


/**
 * Helper function
 */
adsk::core::Ptr<Vector3D> getViewportCameraRightVector() {
    auto camera = app->activeViewport()->camera();

    auto right = camera->upVector();

    auto rotation = Matrix3D::create();
    auto axis = camera->eye()->vectorTo(camera->target());
    rotation->setToRotation(M_PI / 2, axis, Point3D::create(0, 0, 0));
    right->transformBy(rotation);

    return right;
}

/**
 * Helper function
 */
void panViewportCameraByVector(adsk::core::Ptr<Vector3D> vector) {
    auto camera = app->activeViewport()->camera();
    camera->isSmoothTransition(false);

    auto eye = camera->eye();
    eye->translateBy(vector);
    camera->eye(eye);

    auto target = camera->target();
    target->translateBy(vector);
    camera->target(target);

    app->activeViewport()->camera(camera);
    app->activeViewport()->refresh();
}

void orbit(double deltaX, double deltaY) {
    auto camera = app->activeViewport()->camera();
    camera->isSmoothTransition(false);

    auto target = camera->target();
    auto eye = camera->eye();

    // adsk::core::Application::log("-------");
    auto up = camera->upVector();

    // adsk::core::Application::log("TARGET: x: " + std::to_string(target->x()) + " y: " + std::to_string(target->y()) + " z: " + std::to_string(target->z()));
    // adsk::core::Application::log("EYE: x: " + std::to_string(eye->x()) + " y: " + std::to_string(eye->y()) + " z: " + std::to_string(eye->z()));
    // adsk::core::Application::log("CAMERA UP: x: " + std::to_string(up->x()) + " y: " + std::to_string(up->y()) + " z: " + std::to_string(up->z()));

    auto rotation = adsk::core::Matrix3D::create();
    auto z_axis = adsk::core::Vector3D::create(0, 0, 1);
    rotation->setToRotation(M_PI * deltaX / 300, z_axis, target);
    eye->transformBy(rotation);

    // TODO(ibash) the cross product is the right thing, that problem now is
    // that as you pass the (0, 0, 1) (e.g., the top the axis gets flipped,
    // which means you flip back and forth between two half-spaces. So either
    // need to work out of an orgin way outside the half-space (e.g. move
    // everything to a far out orgin, do the rotation, then move back). Or maybe
    // need to keep the axis the same positive / negative directions as when the
    // movement started.
    auto right = camera->upVector();
    auto axis = camera->eye()->vectorTo(camera->target());
    axis = right->crossProduct(axis);

    // adsk::core::Application::log("AXIS: x: " + std::to_string(axis->x()) + " y: " + std::to_string(axis->y()) + " z: " + std::to_string(axis->z()));

    rotation->setToRotation(M_PI * deltaY / 300, axis, target);
    eye->transformBy(rotation);

    camera->eye(eye);
    //camera->upVector(z_axis);
    app->activeViewport()->camera(camera);
    app->activeViewport()->refresh();
}

/**
 * Panning logic
 */
void pan(double deltaX, double deltaY) {
    auto camera = app->activeViewport()->camera();

    if (camera->cameraType() == OrthographicCameraType) {
        auto distance = sqrt(camera->viewExtents());

        deltaX *= distance / 500 * -1;
        deltaY *= distance / 500;
    }
    else {
        auto distance = camera->eye()->distanceTo(camera->target());

        deltaX *= distance / 2000 * -1;
        deltaY *= distance / 2000;
    }

    auto right = getViewportCameraRightVector();
    //adsk::core::Application::log("PAN RIGHT: x: " + std::to_string(right->x()) + " y: " + std::to_string(right->y()) + " z: " + std::to_string(right->z()));

    right->scaleBy(deltaX);
    //adsk::core::Application::log("PAN RIGHT SCALED: x: " + std::to_string(right->x()) + " y: " + std::to_string(right->y()) + " z: " + std::to_string(right->z()));

    auto up = app->activeViewport()->camera()->upVector();
    //adsk::core::Application::log("PAN UP: x: " + std::to_string(up->x()) + " y: " + std::to_string(up->y()) + " z: " + std::to_string(up->z()));


    up->scaleBy(deltaY);
    //adsk::core::Application::log("PAN UP SCALED: x: " + std::to_string(up->x()) + " y: " + std::to_string(up->y()) + " z: " + std::to_string(up->z()));

    right->add(up);
    //adsk::core::Application::log("PAN FINAL VECTOR: x: " + std::to_string(up->x()) + " y: " + std::to_string(up->y()) + " z: " + std::to_string(up->z()));

    panViewportCameraByVector(right);
}


/**
 * Zoom logic
 */
void zoom(double magnification) {
    // TODO zoom to mouse cursor

    auto camera = app->activeViewport()->camera();
    camera->isSmoothTransition(false);

    if (camera->cameraType() == OrthographicCameraType) {
        auto viewExtents = camera->viewExtents();
        camera->viewExtents(viewExtents + viewExtents * -magnification * 2);
    }
    else {
        auto eye = camera->eye();
        auto step = eye->vectorTo(camera->target());

        step->scaleBy(magnification * 0.9);

        eye->translateBy(step);
        camera->eye(eye);
    }

    app->activeViewport()->camera(camera);
    app->activeViewport()->refresh();
}

/**
 * Zoom to fit
 */
void zoomToFit() {
    ui->commandDefinitions()->itemById("FitCommand")->execute();
    app->activeViewport()->refresh();
}

/**
 * This function determines how we handle every event in app
 * Returns:
 * 0 = no change
 * 1 = discard event
 * 2 = pan
 * 3 = zoom
 * 4 = zoom to fit
 * 5 = orbit
 */
int howWeShouldHandleEvent(NSEvent* event) {
    // TODO handle only events to QTCanvas

    if (event.type != NSEventTypeScrollWheel && event.type != NSEventTypeMagnify && event.type != NSEventTypeGesture && event.type != NSEventTypeSmartMagnify) {
        return 0;
    }

    if (!app->activeViewport()) {
        return 0;
    }

    if (![event.window.title hasPrefix: @"Autodesk Fusion 360"]) {
        return 0;
    }

    // shift is for oribting
    // macos will send both NSEventTypeGesture and NSEventTypeScrollWheel, we
    // ignore the former (or else fusion360 will handle orbit too) and handle
    // the latter.

    if ((event.modifierFlags & NSEventModifierFlagShift) &&
        event.type == NSEventTypeGesture) {
      return 1;
    }

    if ((event.modifierFlags & NSEventModifierFlagShift) &&
        event.type == NSEventTypeScrollWheel) {
      return 5;
    }

    // other modified events are passed on to fusion360
    if (event.modifierFlags != 0) {
      return 0;
    }

    if (event.type == NSEventTypeGesture) {
        return 1;
    }

    if (event.type == NSEventTypeScrollWheel) {
        return 2;
    }

    if (event.type == NSEventTypeMagnify) {
        return 3;
    }

    if (event.type == NSEventTypeSmartMagnify) {
        return 4;
    }

    return 0;
}


/**
 * Method swizzling here
 */
@implementation NSApplication (Tracking)
- (void)mySendEvent:(NSEvent *)event {
    int result = howWeShouldHandleEvent(event);
    if (result == 0) {
       [self mySendEvent:event];
    } else if(result == 1) {
        // noop
    } else if(result == 2) {
        pan(event.scrollingDeltaX, event.scrollingDeltaY);
    } else if(result == 3) {
        zoom(event.magnification);
    } else if(result == 4) {
        zoomToFit();
    } else if(result == 5) {
      orbit(event.scrollingDeltaX, event.scrollingDeltaY);
    }
}

- (void)nativeTrackpad {
    Method original = class_getInstanceMethod([self class], @selector(sendEvent:));
    Method swizzled = class_getInstanceMethod([self class], @selector(mySendEvent:));

    method_exchangeImplementations(original, swizzled);
}
@end

/**
 * Main entry here
 */
extern "C" XI_EXPORT bool run(const char* context) {
    app = Application::get();
    if (!app) { return false; }

    ui = app->userInterface();
    if (!ui) { return false; }

    [NSApplication.sharedApplication nativeTrackpad];

    return true;
}

/**
 * Stop overriding events
 */
extern "C" XI_EXPORT bool stop(const char* context) {
    // this is the same as run since we just need to swap the sendEvent implementations back
    app = Application::get();
    if (!app) { return false; }

    ui = app->userInterface();
    if (!ui) { return false; }

    [NSApplication.sharedApplication nativeTrackpad];

    return true;
}
