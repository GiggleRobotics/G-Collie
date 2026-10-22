#include <jni.h>
#include <stdlib.h>
#include "_cgo_export.h"
static jstring answer(JNIEnv *env, char *value) {jstring result=(*env)->NewStringUTF(env,value);free(value);return result;}
JNIEXPORT jstring JNICALL Java_dev_giggle_gcollie_NativeNetwork_start(JNIEnv *env,jclass cls,jstring dir){const char *v=(*env)->GetStringUTFChars(env,dir,0);char *r=GCStart((char*)v);(*env)->ReleaseStringUTFChars(env,dir,v);return answer(env,r);}
JNIEXPORT jstring JNICALL Java_dev_giggle_gcollie_NativeNetwork_status(JNIEnv *env,jclass cls){return answer(env,GCStatus());}
JNIEXPORT jstring JNICALL Java_dev_giggle_gcollie_NativeNetwork_login(JNIEnv *env,jclass cls){return answer(env,GCLogin());}
JNIEXPORT jstring JNICALL Java_dev_giggle_gcollie_NativeNetwork_open(JNIEnv *env,jclass cls,jstring raw){const char *v=(*env)->GetStringUTFChars(env,raw,0);char *r=GCOpen((char*)v);(*env)->ReleaseStringUTFChars(env,raw,v);return answer(env,r);}
JNIEXPORT jstring JNICALL Java_dev_giggle_gcollie_NativeNetwork_logout(JNIEnv *env,jclass cls){return answer(env,GCLogout());}
JNIEXPORT void JNICALL Java_dev_giggle_gcollie_NativeNetwork_stop(JNIEnv *env,jclass cls){GCStop();}
JNIEXPORT jstring JNICALL Java_dev_giggle_gcollie_NativeNetwork_configureNetwork(JNIEnv *env,jclass cls,jstring raw){const char *v=(*env)->GetStringUTFChars(env,raw,0);char *r=GCConfigureNetwork((char*)v);(*env)->ReleaseStringUTFChars(env,raw,v);return answer(env,r);}
