#ifndef STM_SPEECH_BRIDGE_H
#define STM_SPEECH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

char *STMAddPunctuation(const char *model_directory, const char *text, char **error_message);
void STMPunctuationReset(void);
void STMFreeString(char *value);

unsigned char *STMWebPEncodeRGBA(
    const unsigned char *rgba,
    int width,
    int height,
    int stride,
    float quality,
    unsigned long *output_size
);
void STMWebPFree(void *value);

#ifdef __cplusplus
}
#endif

#endif
