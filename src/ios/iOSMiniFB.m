#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach/mach_time.h>
#include <MiniFB.h>
#include "MiniFB_internal.h"
#include "WindowData.h"
#include "WindowData_IOS.h"
#include "iOSViewController.h"

//-------------------------------------
SWindowData *
create_window_data(unsigned width, unsigned height) {
    SWindowData *window_data;
    
    window_data = malloc(sizeof(SWindowData));
    if(window_data == 0x0) {
        NSLog(@"Cannot allocate window data");
        return 0x0;
    }
    memset(window_data, 0, sizeof(SWindowData));

    SWindowData_IOS *window_data_ios = malloc(sizeof(SWindowData_IOS));
    if(window_data_ios == 0x0) {
        free(window_data);
        NSLog(@"Cannot allocate ios window data");
        return 0x0;
    }
    memset((void *) window_data_ios, 0, sizeof(SWindowData_IOS));

    float scale = [UIScreen mainScreen].scale;

    window_data->specific      = window_data_ios;

    window_data->window_width  = [UIScreen mainScreen].bounds.size.width  * scale;
    window_data->window_height = [UIScreen mainScreen].bounds.size.height * scale;

    window_data->dst_width     = width;
    window_data->dst_height    = height;

    window_data->buffer_width  = width;
    window_data->buffer_height = height;
    window_data->buffer_stride = width * 4;

    window_data->draw_buffer   = malloc(width * height * 4);
    if (!window_data->draw_buffer) {
        free(window_data);
        free(window_data_ios);
        NSLog(@"Unable to create draw buffer");
        return 0x0;
    }
    
    return window_data;
}

//-------------------------------------
struct mfb_window *
mfb_open(const char *title, unsigned width, unsigned height) {
    return mfb_open_ex(title, width, height, 0);
}

//-------------------------------------
struct mfb_window *
mfb_open_ex(const char *title, unsigned width, unsigned height, unsigned flags) {
    UIWindow    *window;
    NSArray     *windows;
    size_t      numWindows;

    kUnused(title);
    kUnused(flags);
    
    SWindowData *window_data = create_window_data(width, height);
    if (window_data == 0x0) {
        return 0x0;
    }
    SWindowData_IOS *window_data_ios = (SWindowData_IOS *) window_data->specific;
    
    static Vertex s_vertices[4] = {
        {-1.0, -1.0, 0, 1},
        {-1.0,  1.0, 0, 1},
        { 1.0, -1.0, 0, 1},
        { 1.0,  1.0, 0, 1},
    };
    memcpy(window_data_ios->vertices, s_vertices, sizeof(s_vertices));

    windows = [[UIApplication sharedApplication] windows];
    numWindows = [windows count];
    if(numWindows > 0) {
        window = [windows objectAtIndex:0];
    }
    else {
        // Notice that you need to set "Launch Screen File" in:
        // project > executable > general
        // to get the real size with [UIScreen mainScreen].bounds].
        window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        NSLog(@"UIApplication has no window. We create one (%f, %f).", [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    }
    
    if([window.rootViewController isKindOfClass:[iOSViewController class]] == false) {
        iOSViewController *controller = [[iOSViewController alloc] initWithWindowData:window_data];
        [window setRootViewController:controller];
#if !__has_feature(objc_arc)
        [controller release];
#endif
        controller = (iOSViewController *) window.rootViewController;
    }
    else {
        ((iOSViewController *) window.rootViewController)->window_data = window_data;
    }
    [window makeKeyAndVisible];

    return (struct mfb_window *) window_data;
}

//-------------------------------------
static void
destroy_window_data(SWindowData *window_data) {
    if(window_data == 0x0)
        return;

    @autoreleasepool {
        SWindowData_IOS   *window_data_ios = (SWindowData_IOS *) window_data->specific;
        if(window_data_ios != 0x0) {
            memset((void *) window_data_ios, 0, sizeof(SWindowData_IOS));
            free(window_data_ios);
        }
        memset(window_data, 0, sizeof(SWindowData));
        free(window_data);
    }
}

//-------------------------------------
mfb_update_state
mfb_update(struct mfb_window *window, void *buffer) {
    if(window == 0x0) {
        return STATE_INVALID_WINDOW;
    }

    SWindowData *window_data = (SWindowData *) window;
    if(window_data->close) {
        destroy_window_data(window_data);
        return STATE_EXIT;
    }

    if(buffer == 0x0) {
        return STATE_INVALID_BUFFER;
    }

    memcpy(window_data->draw_buffer, buffer, window_data->buffer_width * window_data->buffer_height * 4);

    return STATE_OK;
}

//-------------------------------------
mfb_update_state
mfb_update_events(struct mfb_window *window) {
    kUnused(window);
    return STATE_OK;
}

//-------------------------------------
extern double   g_time_for_frame;

bool
mfb_wait_sync(struct mfb_window *window) {
    kUnused(window);
    return true;
}

//-------------------------------------
bool
mfb_set_viewport(struct mfb_window *window, unsigned offset_x, unsigned offset_y, unsigned width, unsigned height) {
    SWindowData *window_data = (SWindowData *) window;

    if(offset_x + width > window_data->window_width) {
        return false;
    }
    if(offset_y + height > window_data->window_height) {
        return false;
    }

    window_data->dst_offset_x = offset_x;
    window_data->dst_offset_y = offset_y;
    window_data->dst_width    = width;
    window_data->dst_height   = height;

    float x1 =  ((float) offset_x           / window_data->window_width)  * 2.0f - 1.0f;
    float x2 = (((float) offset_x + width)  / window_data->window_width)  * 2.0f - 1.0f;
    float y1 =  ((float) offset_y           / window_data->window_height) * 2.0f - 1.0f;
    float y2 = (((float) offset_y + height) / window_data->window_height) * 2.0f - 1.0f;

    SWindowData_IOS *window_data_ios = (SWindowData_IOS *) window_data->specific;

    window_data_ios->vertices[0].x = x1;
    window_data_ios->vertices[0].y = y1;

    window_data_ios->vertices[1].x = x1;
    window_data_ios->vertices[1].y = y2;

    window_data_ios->vertices[2].x = x2;
    window_data_ios->vertices[2].y = y1;

    window_data_ios->vertices[3].x = x2;
    window_data_ios->vertices[3].y = y2;

    return true;
}

//-------------------------------------
extern double   g_timer_frequency;
extern double   g_timer_resolution;

uint64_t
mfb_timer_tick() {
    static mach_timebase_info_data_t    timebase = { 0 };

    if (timebase.denom == 0) {
        (void) mach_timebase_info(&timebase);
    }
    
    uint64_t time = mach_absolute_time();

    //return (time * s_timebase_info.numer) / s_timebase_info.denom;

    // Perform the arithmetic at 128-bit precision to avoid the overflow!
    uint64_t high    = (time >> 32) * timebase.numer;
    uint64_t highRem = ((high % timebase.denom) << 32) / timebase.denom;
    uint64_t low     = (time & 0xFFFFFFFFull) * timebase.numer / timebase.denom;
    high /= timebase.denom;
    
    return (high << 32) + highRem + low;
}

//-------------------------------------
void
mfb_timer_init() {
    g_timer_frequency  = 1e+9;
    g_timer_resolution = 1.0 / g_timer_frequency;
}
