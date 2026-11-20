package com.ryanheise.audioservice;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** MU-FLAC: handles the heart button of the custom notification. */
public class MuActionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !AudioService.MU_ACTION_FAVORITE.equals(intent.getAction())) return;
        Runnable listener = AudioService.muFavoriteListener;
        if (listener != null) listener.run();
    }
}
