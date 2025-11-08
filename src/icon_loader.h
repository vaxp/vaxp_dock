#ifndef ICON_LOADER_H
#define ICON_LOADER_H

void init_gtk();
char* get_icon_path(const char* icon_name, int size);
void free_icon_path(char* path);

#endif