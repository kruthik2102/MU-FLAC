package com.ryanheise.audioservice;

/**
 * MU-FLAC: plain bridge between the app module and the custom notification.
 * The app must not reference AudioService directly (its androidx.media
 * supertype is not on the app's compile classpath).
 */
public final class MuNotificationBridge {
    private MuNotificationBridge() {}

    /** Called when the notification's heart is tapped. */
    public static volatile Runnable favoriteListener;

    /** Heart state of the current track. */
    public static void setFavorite(boolean favorite) {
        AudioService.setMuFavorite(favorite);
    }
}
