package com.teamelo.dungeonchasers.ads;

import android.app.Activity;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.UserMessagingPlatform;
import com.secmtp.sdk.core.api.ATSDK;
import com.secmtp.sdk.core.api.ATSDKInitListener;
import com.secmtp.sdk.core.api.ATAdInfo;
import com.secmtp.sdk.core.api.AdError;
import com.secmtp.sdk.rewardvideo.api.ATRewardVideoAd;
import com.secmtp.sdk.rewardvideo.api.ATRewardVideoListener;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;

public final class DungeonAds extends GodotPlugin {
    private final JSONArray events = new JSONArray();
    private ATRewardVideoAd ad;
    private boolean initialized, initializing, loading;
    private String activeId = "";
    private boolean rewarded;
    private int generation;
    private boolean consentFormOpen;

    public DungeonAds(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "DungeonAds"; }

    private void event(String type, String id) {
        synchronized (events) {
            JSONObject value = new JSONObject();
            try { value.put("type", type); value.put("id", id); }
            catch (org.json.JSONException ignored) { return; }
            events.put(value);
        }
    }

    @UsedByGodot public String poll_events() {
        synchronized (events) {
            String result = events.toString();
            while (events.length() > 0) events.remove(events.length() - 1);
            return result;
        }
    }

    @UsedByGodot public void configure(String appId, String appKey, String placement) {
        runOnUiThread(() -> {
            if (initialized) { event("initialized", ""); return; }
            if (initializing) return;
            if (consentFormOpen) { event("init_failed", ""); return; }
            Activity activity = getActivity();
            if (activity == null) { event("init_failed", ""); return; }
            initializing = true;
            final int attempt = generation;
            ConsentInformation consent = UserMessagingPlatform.getConsentInformation(activity);
            consent.requestConsentInfoUpdate(activity, new ConsentRequestParameters.Builder().build(), () -> {
                if (attempt != generation) return;
                consentFormOpen = true;
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity, error -> {
                    consentFormOpen = false;
                    if (attempt != generation) return;
                    if (consent.canRequestAds()) initialize(appId, appKey, placement, attempt);
                    else { initializing = false; event("init_failed", ""); }
                });
            }, error -> {
                    if (attempt != generation) return;
                    if (consent.canRequestAds()) initialize(appId, appKey, placement, attempt);
                    else { initializing = false; event("init_failed", ""); }
                });
        });
    }

    @UsedByGodot public void reset_preparation() {
        runOnUiThread(() -> {
            if (!activeId.isEmpty()) return;
            generation++;
            initializing = false;
            loading = false;
        });
    }

    private void initialize(String appId, String appKey, String placement, int attempt) {
        ATSDK.init(getActivity(), appId, appKey, null, new ATSDKInitListener() {
            @Override public void onSuccess() {
                runOnUiThread(() -> {
                    if (attempt != generation) return;
                    initialized = true;
                    initializing = false;
                    ad = new ATRewardVideoAd(getActivity(), placement);
                    ad.setAdListener(new ATRewardVideoListener() {
                        public void onRewardedVideoAdLoaded() { runOnUiThread(() -> { loading = false; event("ready", ""); }); }
                        public void onRewardedVideoAdFailed(AdError error) { runOnUiThread(() -> { loading = false; event("load_failed", ""); }); }
                        public void onRewardedVideoAdPlayStart(ATAdInfo info) { }
                        public void onRewardedVideoAdPlayEnd(ATAdInfo info) { }
                        public void onRewardedVideoAdPlayClicked(ATAdInfo info) { }
                        public void onReward(ATAdInfo info) {
                            runOnUiThread(() -> {
                                if (!activeId.isEmpty() && !rewarded) { rewarded = true; event("reward", activeId); }
                            });
                        }
                        public void onRewardedVideoAdPlayFailed(AdError error, ATAdInfo info) { runOnUiThread(() -> finish("show_failed")); }
                        public void onRewardedVideoAdClosed(ATAdInfo info) { runOnUiThread(() -> finish("closed")); }
                    });
                    event("initialized", "");
                });
            }
            @Override public void onFail(String error) {
                runOnUiThread(() -> {
                    if (attempt != generation) return;
                    initializing = false;
                    event("init_failed", "");
                });
            }
        });
    }

    private void finish(String kind) {
        if (activeId.isEmpty()) return;
        event(kind, activeId);
        activeId = "";
    }

    @UsedByGodot public void load_rewarded() {
        runOnUiThread(() -> {
            if (getActivity() == null || !UserMessagingPlatform.getConsentInformation(getActivity()).canRequestAds()) {
                event("load_failed", ""); return;
            }
            if (!initialized || ad == null) { event("load_failed", ""); return; }
            if (ad.isAdReady()) { event("ready", ""); return; }
            if (!loading && activeId.isEmpty()) { loading = true; ad.load(); }
        });
    }

    @UsedByGodot public void show_rewarded(String requestId, String scene) {
        runOnUiThread(() -> {
            if (ad == null || !ad.isAdReady() || getActivity() == null || !activeId.isEmpty()
                    || !UserMessagingPlatform.getConsentInformation(getActivity()).canRequestAds()) {
                event("show_failed", requestId);
                return;
            }
            activeId = requestId;
            rewarded = false;
            // Gameplay point names are not TopOn's generated scenario IDs.
            ad.show(getActivity());
        });
    }

    @UsedByGodot public void privacy_options() {
        runOnUiThread(() -> {
            if (getActivity() != null)
                UserMessagingPlatform.showPrivacyOptionsForm(getActivity(), error -> { });
        });
    }

    @Override public void onMainDestroy() {
        if (ad != null) ad.destroyAd();
        ad = null;
        initialized = false;
        super.onMainDestroy();
    }
}
