#include <gtk/gtk.h>
#include <gdk/gdk.h>
#include <stdlib.h>
#include <string.h>

// Initialize GTK (call this once at startup)
void init_gtk() {
    if (!gtk_init_check(NULL, NULL)) {
        fprintf(stderr, "Failed to initialize GTK\n");
    }
}

// Load icon and return the path to the icon file
char* get_icon_path(const char* icon_name, int size) {
    GtkIconTheme* theme = gtk_icon_theme_get_default();
    if (!theme) return NULL;

    GtkIconInfo* info = gtk_icon_theme_lookup_icon(theme, icon_name, size, GTK_ICON_LOOKUP_FORCE_SIZE);
    if (!info) return NULL;

    const char* path = gtk_icon_info_get_filename(info);
    char* result = path ? strdup(path) : NULL;
    
    g_object_unref(info);
    return result;
}

// Free the memory allocated for the icon path
void free_icon_path(char* path) {
    free(path);
}