#include "my_application.h"
#include <flutter_linux/flutter_linux.h>
#include "flutter/generated_plugin_registrant.h"

#ifdef GDK_WINDOWING_X11
extern "C" {
  #include <gdk/gdkx.h>
  #include <X11/Xlib.h>
  #include <X11/Xatom.h>
}
#endif

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // ✅ الإضافة لحفظ الحجم والهامش
  int window_height;
  int window_width;
  int bottom_margin; // ✅ تمت إضافة هذا
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView *view) {
  // إظهار النافذة
  GtkWidget* window_widget = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_widget_show(window_widget);

  // --- تطبيق خصائص X11 ---
#ifdef GDK_WINDOWING_X11
  GdkWindow* gdk_window = gtk_widget_get_window(window_widget);
  if (GDK_IS_X11_WINDOW(gdk_window)) {
    GdkDisplay* display = gtk_widget_get_display(window_widget);
    Display* xdisplay = GDK_DISPLAY_XDISPLAY(display);
    Window xid = GDK_WINDOW_XID(gdk_window);

    // --- استرجاع المتغيرات ---
    int window_height = self->window_height;
    int window_width = self->window_width;
    int bottom_margin = self->bottom_margin; // ✅ استرجاع الهامش

    // اجعلها دائمًا على كل الأسطح
    Atom state_atom = XInternAtom(xdisplay, "_NET_WM_STATE", False);
    Atom state_sticky = XInternAtom(xdisplay, "_NET_WM_STATE_STICKY", False);
    Atom state_above = XInternAtom(xdisplay, "_NET_WM_STATE_ABOVE", False);
    Atom states[2] = {state_sticky, state_above};
    XChangeProperty(xdisplay, xid, state_atom, XA_ATOM, 32, PropModeReplace,
                    reinterpret_cast<unsigned char*>(states), 2);

    // --- ✅ التصحيح النهائي لمؤشرات 'strut' (لحجز المساحة + الهامش) ---
    Atom strut_atom = XInternAtom(xdisplay, "_NET_WM_STRUT_PARTIAL", False);
    Atom strut_atom_fallback = XInternAtom(xdisplay, "_NET_WM_STRUT", False);
    long strut[12] = {0};

    // --- ✅ التعديل هنا: حجز مساحة النافذة + الهامش السفلي ---
    // المساحة المحجوزة من الأسفل = ارتفاع النافذة + الهامش
    strut[3] = window_height + bottom_margin; // bottom
    strut[10] = 0;            // bottom_start_x
    strut[11] = window_width; // bottom_end_x
    // --- نهاية التعديل ---

    XChangeProperty(xdisplay, xid, strut_atom, XA_CARDINAL, 32, PropModeReplace,
                    reinterpret_cast<unsigned char*>(strut), 12);
    XChangeProperty(xdisplay, xid, strut_atom_fallback, XA_CARDINAL, 32, PropModeReplace,
                    reinterpret_cast<unsigned char*>(strut), 4);

    XSetInputFocus(xdisplay, None, RevertToNone, CurrentTime);
    XFlush(xdisplay);
  }
#endif
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  GtkWidget* window_widget = GTK_WIDGET(window);

  gtk_widget_set_app_paintable(window_widget, TRUE);
  GdkScreen* screen = gtk_window_get_screen(window);

#if GTK_CHECK_VERSION(3, 0, 0)
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(window_widget, visual);
  }
#endif

  // إعدادات العرض
  GdkDisplay* display = gtk_widget_get_display(window_widget);
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  GdkRectangle monitor_geometry;
  gdk_monitor_get_geometry(monitor, &monitor_geometry);
  double scale_factor = gdk_monitor_get_scale_factor(monitor);

  int window_height = 60 * scale_factor;
  int window_width = monitor_geometry.width;
  int bottom_margin = 4 * scale_factor; // ✅ تحديد الهامش السفلي (مع مراعاة الـ scale)

  // --- ✅ حفظ المتغيرات لاستخدامها في 'first_frame_cb' ---
  self->window_height = window_height;
  self->window_width = window_width;
  self->bottom_margin = bottom_margin; // ✅ حفظ الهامش

  gtk_window_set_default_size(window, window_width, window_height);
  gtk_widget_set_size_request(window_widget, window_width, window_height);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_stick(window);
  gtk_window_set_keep_above(window, TRUE);

  // --- إخبار GTK بنوع النافذة (قبل realize) ---
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DOCK);

  gtk_widget_realize(window_widget);
  
  // --- ✅ التعديل هنا: تحريك النافذة لأسفل الشاشة مع هامش 4 بكسل ---
  // الإحداثي الصادي (Y) = (ارتفاع الشاشة - ارتفاع النافذة - الهامش السفلي)
  gtk_window_move(window, 0, monitor_geometry.height - window_height - bottom_margin);
  // --- نهاية التعديل ---

  // إنشاء مشروع Flutter
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);

  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "rgba(0, 0, 0, 0)");
  fl_view_set_background_color(view, &background_color);

  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // استدعاء 'first_frame_cb' عند جاهزية Flutter
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
















// #include "my_application.h"
// #include <flutter_linux/flutter_linux.h>
// #include "flutter/generated_plugin_registrant.h"

// #ifdef GDK_WINDOWING_X11
// extern "C" {
//   #include <gdk/gdkx.h>
//   #include <X11/Xlib.h>
//   #include <X11/Xatom.h>
// }
// #endif

// struct _MyApplication {
//   GtkApplication parent_instance;
//   char** dart_entrypoint_arguments;
//   // الإضافة لحفظ الحجم
//   int window_height;
//   int window_width;
// };

// G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// static void first_frame_cb(MyApplication* self, FlView *view) {
//   // إظهار النافذة (كان موجوداً أصلاً)
//  GtkWidget* window_widget = gtk_widget_get_toplevel(GTK_WIDGET(view));  gtk_widget_show(window_widget);

//   // --- تطبيق خصائص X11 الآن (بعد تحميل Flutter) ---
// #ifdef GDK_WINDOWING_X11
//   GdkWindow* gdk_window = gtk_widget_get_window(window_widget);
//   if (GDK_IS_X11_WINDOW(gdk_window)) {
//     GdkDisplay* display = gtk_widget_get_display(window_widget);
//     Display* xdisplay = GDK_DISPLAY_XDISPLAY(display);
//     Window xid = GDK_WINDOW_XID(gdk_window);

//     // --- استرجاع المتغيرات ---
//     int window_height = self->window_height;
//     int window_width = self->window_width;

//     // اجعلها دائمًا على كل الأسطح
//     Atom state_atom = XInternAtom(xdisplay, "_NET_WM_STATE", False);
//     Atom state_sticky = XInternAtom(xdisplay, "_NET_WM_STATE_STICKY", False);
//     Atom state_above = XInternAtom(xdisplay, "_NET_WM_STATE_ABOVE", False);
//     Atom states[2] = {state_sticky, state_above};
//     XChangeProperty(xdisplay, xid, state_atom, XA_ATOM, 32, PropModeReplace,
//                     reinterpret_cast<unsigned char*>(states), 2);

//     // --- ✅ التصحيح النهائي لمؤشرات 'strut' (تم التعديل للأسفل) ---
//     Atom strut_atom = XInternAtom(xdisplay, "_NET_WM_STRUT_PARTIAL", False);
//     Atom strut_atom_fallback = XInternAtom(xdisplay, "_NET_WM_STRUT", False);
//     long strut[12] = {0};

//     // --- ✅ التعديل هنا: عكس العملية لحجز مساحة في الأسفل (bottom) ---
//     // strut[2] (top) أصبح 0
//     strut[3] = window_height; // bottom (القيمة السابقة لـ strut[2])
    
//     // strut[8] و strut[9] (top_start/end) أصبحا 0
//     strut[10] = 0;            // bottom_start_x (القيمة السابقة لـ strut[8])
//     strut[11] = window_width; // bottom_end_x (القيمة السابقة لـ strut[9])
//     // --- نهاية التعديل ---

//     XChangeProperty(xdisplay, xid, strut_atom, XA_CARDINAL, 32, PropModeReplace,
//                     reinterpret_cast<unsigned char*>(strut), 12);
//     XChangeProperty(xdisplay, xid, strut_atom_fallback, XA_CARDINAL, 32, PropModeReplace,
//                     reinterpret_cast<unsigned char*>(strut), 4);

//     XSetInputFocus(xdisplay, None, RevertToNone, CurrentTime);
//     XFlush(xdisplay);
//   }
// #endif
// }

// static void my_application_activate(GApplication* application) {
//   MyApplication* self = MY_APPLICATION(application);
//   GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
//   GtkWidget* window_widget = GTK_WIDGET(window);

//   gtk_widget_set_app_paintable(window_widget, TRUE);
//   GdkScreen* screen = gtk_window_get_screen(window);

// #if GTK_CHECK_VERSION(3, 0, 0)
//   GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
//   if (visual != nullptr) {
//     gtk_widget_set_visual(window_widget, visual);
//   }
// #endif

//   // إعدادات العرض
//   GdkDisplay* display = gtk_widget_get_display(window_widget);
//   GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
//   GdkRectangle monitor_geometry;
//   gdk_monitor_get_geometry(monitor, &monitor_geometry);
//   double scale_factor = gdk_monitor_get_scale_factor(monitor);

//   int window_height = 60 * scale_factor;
//   int window_width = monitor_geometry.width;

//   // --- حفظ المتغيرات لاستخدامها في 'first_frame_cb' ---
//   self->window_height = window_height;
//   self->window_width = window_width;

//   gtk_window_set_default_size(window, window_width, window_height);
//   gtk_widget_set_size_request(window_widget, window_width, window_height);
//   gtk_window_set_decorated(window, FALSE);
//   gtk_window_stick(window);
//   gtk_window_set_keep_above(window, TRUE);

//   // --- إخبار GTK بنوع النافذة (قبل realize) ---
//   gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DOCK);

//   gtk_widget_realize(window_widget);
  
//   // --- ✅ التعديل هنا: تحريك النافذة لأسفل الشاشة ---
//   // الإحداثي السيني (X) هو 0 (لأنه ملء الشاشة)
//   // الإحداثي الصادي (Y) هو (ارتفاع الشاشة - ارتفاع النافذة)
//   gtk_window_move(window, 0, monitor_geometry.height - window_height);
//   // --- نهاية التعديل ---

//   // --- ⛔️ تم حذف كل كود X11 من هنا ونقله إلى 'first_frame_cb' (كما في الكود الأصلي) ---

//   // إنشاء مشروع Flutter
//   g_autoptr(FlDartProject) project = fl_dart_project_new();
//   fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

//   FlView* view = fl_view_new(project);

//   GdkRGBA background_color;
//   gdk_rgba_parse(&background_color, "rgba(0,0,0,0.3)"); // تصحيح gdk_rgba_parse
//   fl_view_set_background_color(view, &background_color);

//   gtk_widget_show(GTK_WIDGET(view));
//   gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

//   // --- هذا السطر يستدعي 'first_frame_cb' عند جاهزية Flutter ---
//   g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
//   fl_register_plugins(FL_PLUGIN_REGISTRY(view));

//   gtk_widget_grab_focus(GTK_WIDGET(view));
// }

// static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
//   MyApplication* self = MY_APPLICATION(application);
//   self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

//   g_autoptr(GError) error = nullptr;
//   if (!g_application_register(application, nullptr, &error)) {
//     g_warning("Failed to register: %s", error->message);
//     *exit_status = 1;
//     return TRUE;
//   }

//   g_application_activate(application);
//   *exit_status = 0;
//   return TRUE;
// }

// static void my_application_startup(GApplication* application) {
//   G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
// }

// static void my_application_shutdown(GApplication* application) {
//   G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
// }

// static void my_application_dispose(GObject* object) {
//   MyApplication* self = MY_APPLICATION(object);
//   g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
//   G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
// }

// static void my_application_class_init(MyApplicationClass* klass) {
//   G_APPLICATION_CLASS(klass)->activate = my_application_activate;
//   G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
//   G_APPLICATION_CLASS(klass)->startup = my_application_startup;
//   G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
//   G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
// }

// static void my_application_init(MyApplication* self) {}

// MyApplication* my_application_new() {
//   g_set_prgname(APPLICATION_ID);
//   return MY_APPLICATION(g_object_new(my_application_get_type(),
//                                      "application-id", APPLICATION_ID,
//                                      "flags", G_APPLICATION_NON_UNIQUE,
//                                      nullptr));
// }