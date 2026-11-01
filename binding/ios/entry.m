#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL_main.h>

extern SDL_AppResult odin_app_Init(void **, int, char **);
extern SDL_AppResult odin_app_Iterate(void *);
extern SDL_AppResult odin_app_Event(void *, SDL_Event *);
extern void odin_app_Quit(void *, SDL_AppResult);
SDL_AppResult SDL_AppInit(void **s, int n, char **v) { return odin_app_Init(s, n, v); }
SDL_AppResult SDL_AppIterate(void *s) { return odin_app_Iterate(s); }
SDL_AppResult SDL_AppEvent(void *s, SDL_Event *e) { return odin_app_Event(s, e); }
void SDL_AppQuit(void *s, SDL_AppResult r) { odin_app_Quit(s, r); }
