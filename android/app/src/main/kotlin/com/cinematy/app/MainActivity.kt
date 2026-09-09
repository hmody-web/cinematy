package com.cinematy.app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Build
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.util.Rational
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import android.view.animation.DecelerateInterpolator
import com.example.liquidglass.GlassMaterial
import com.example.liquidglass.LiquidGlassTabBar
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android host for Cinematy.
 *
 * The bottom navigation is a real Android View from
 * QWEA0/Liquid-Glass-Android, not a Flutter imitation. Flutter is rendered
 * through a TextureView so the native glass can sample/refract the live Flutter
 * scene behind it with the library's GPU pipeline.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "cinematy/native_android_liquid_tab_bar"
        private const val PIP_CHANNEL = "cinematy/system_pip"
        private const val BAR_HEIGHT_DP = 62
        private const val BAR_SIDE_MARGIN_DP = 14
        private const val BAR_BOTTOM_GAP_DP = 14
        private const val PHONE_MAX_BAR_WIDTH_DP = 430
        private const val TABLET_MAX_BAR_WIDTH_DP = 560
        private const val TABLET_BREAKPOINT_DP = 600
        private const val ANIMATION_MS = 500L
        private const val BRAND_RED = 0xFFFF473D.toInt()
    }

    private var methodChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null
    private var tvPipActive = false
    private var liquidTabBar: LiquidGlassTabBar? = null
    private var barContainer: FrameLayout? = null
    private var flutterBackdrop: FlutterView? = null

    private var pendingIndex = 0
    private var pendingCompact = false
    private var pendingVisible = true
    private var syncingFromFlutter = false
    private var touchingBar = false
    private var appliedVisible: Boolean? = null
    private var appliedFontFamily: String? = null
    private var scaleAnimator: ValueAnimator? = null

    // Critical for true native refraction over Flutter. With Flutter's default
    // SurfaceView the Android View hierarchy cannot sample the pixels behind it.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success(liquidTabBar != null)
                    "setIndex" -> {
                        val raw = call.arguments
                        val index = when (raw) {
                            is Int -> raw
                            is Number -> raw.toInt()
                            else -> raw?.toString()?.toIntOrNull()
                        }?.coerceIn(0, 4) ?: 0
                        if (pendingIndex != index) {
                            pendingIndex = index
                            applySelectedIndex(index)
                        }
                        result.success(null)
                    }
                    "setCompact" -> {
                        val compact = call.arguments as? Boolean ?: false
                        if (pendingCompact != compact) {
                            pendingCompact = compact
                            animateBarScale()
                        }
                        result.success(null)
                    }
                    "setFontFamily" -> {
                        val family = call.arguments?.toString()?.takeIf { it.isNotBlank() } ?: "Monadi"
                        applyAppTypeface(family)
                        result.success(null)
                    }
                    "setVisible" -> {
                        val visible = call.arguments as? Boolean ?: true
                        pendingVisible = visible
                        applyBarVisibility(visible)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setActive" -> {
                        tvPipActive = call.arguments as? Boolean ?: false
                        updatePictureInPictureParams()
                        result.success(null)
                    }
                    "enter" -> {
                        val entered = enterTvPictureInPicture()
                        result.success(entered)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (tvPipActive && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterTvPictureInPicture()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            barContainer?.visibility = View.GONE
        } else {
            applyBarVisibility(pendingVisible, immediate = true)
        }
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    private fun buildTvPictureInPictureParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(tvPipActive)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun updatePictureInPictureParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val params = buildTvPictureInPictureParams() ?: return
        setPictureInPictureParams(params)
    }

    private fun enterTvPictureInPicture(): Boolean {
        if (!tvPipActive || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = buildTvPictureInPictureParams() ?: return false
            setPictureInPictureParams(params)
            enterPictureInPictureMode(params)
        } catch (_: Throwable) {
            false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Flutter installs its root after super.onCreate. Posting guarantees the
        // FlutterView exists before we attach the native glass overlay.
        findViewById<ViewGroup>(android.R.id.content)?.post {
            installLiquidGlassTabBar()
        }
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        pipChannel?.setMethodCallHandler(null)
        pipChannel = null
        scaleAnimator?.cancel()
        scaleAnimator = null
        liquidTabBar = null
        barContainer = null
        flutterBackdrop = null
        super.onDestroy()
    }

    private fun installLiquidGlassTabBar() {
        if (liquidTabBar != null || isFinishing || isDestroyed) return

        val root = findViewById<ViewGroup>(android.R.id.content) ?: return
        root.clipChildren = false
        root.clipToPadding = false

        // Capture only Flutter, never the bar itself. This prevents recursive
        // sampling and gives the lens the exact pixels visible under the dock.
        flutterBackdrop = findFlutterView(root)

        val bar = LiquidGlassTabBar(this).apply {
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            textDirection = View.TEXT_DIRECTION_RTL
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES

            // LiquidGlassTabBar lays its slots from physical left to right even
            // when the host View is RTL. Feed it the visual order explicitly so
            // Cinematy remains truly RTL: Home is always the right-most tab.
            setTabs(
                listOf(
                    LiquidGlassTabBar.TabItem("مكتبتي", resources.getDrawable(R.drawable.ic_nav_library, theme)),
                    LiquidGlassTabBar.TabItem("التلفاز", resources.getDrawable(R.drawable.ic_nav_tv, theme)),
                    LiquidGlassTabBar.TabItem("البحث", resources.getDrawable(R.drawable.ic_nav_search, theme)),
                    LiquidGlassTabBar.TabItem("اكتشف", resources.getDrawable(R.drawable.ic_nav_explore, theme)),
                    LiquidGlassTabBar.TabItem("الرئيسية", resources.getDrawable(R.drawable.ic_nav_home, theme)),
                )
            )

            selectedTintColor = BRAND_RED

            // Use the library's real glass/lens pipeline rather than painting a
            // translucent rectangle ourselves.
            material = GlassMaterial.CLEAR
            enableDynamicBackground = true
            enableBackdropBlur = true
            enableChromaticAberration = true
            enableChromaticDispersion = true
            enableSensorHighlight = true
            enableAdaptiveTint = true
            enableEdgeHighlight = true
            edgeHighlightOpacity = 42f
            edgeHighlightBorderWidth = dpF(0.8f)
            enableShadow = false
            collectFrameStats = false

            cornerRadius = dpF(30f)
            refractionHeight = dpF(52f)
            bevelWidth = dpF(11f)
            dispersionStrength = 0.085f
            blurAmount = 0.055f
            saturation = 138f
            aberrationIntensity = 1.35f
            displacementScale = 58f
            elasticity = 0.17f
            downsampleScale = 2
            highQualityBlur = false

            // Very light neutral tint: enough readability without faking a
            // black/white gradient. The real backdrop remains visible/refracted.
            setGlassTint(Color.BLACK, 0.075f)

            flutterBackdrop?.let { backdropSource = it }

            onTabSelected = { nativeIndex ->
                if (!syncingFromFlutter) {
                    val flutterIndex = 4 - nativeIndex
                    pendingIndex = flutterIndex
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    methodChannel?.invokeMethod("tabChanged", flutterIndex)
                }
            }

            // Preserve the requested 0.5% whole-bar press response while the
            // library keeps full control of the droplet drag underneath.
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        touchingBar = true
                        animateBarScale()
                    }
                    MotionEvent.ACTION_UP,
                    MotionEvent.ACTION_CANCEL -> {
                        touchingBar = false
                        animateBarScale()
                    }
                }
                false
            }
        }

        // Put the native tab bar inside a dedicated centered LTR container.
        // We scale THIS container instead of the RTL tab bar itself. On some
        // phone layouts an RTL View can visually appear anchored to its start
        // edge while scaling; the neutral wrapper makes the transform origin
        // unambiguously the physical center of the dock.
        val holder = FrameLayout(this).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            clipChildren = false
            clipToPadding = false
            pivotX = 0f
            pivotY = 0f
        }
        holder.addView(
            bar,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        )

        val params = FrameLayout.LayoutParams(
            calculateBarWidthPx(root.width),
            dp(BAR_HEIGHT_DP),
        ).apply {
            gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
            leftMargin = 0
            rightMargin = 0
            bottomMargin = dp(BAR_BOTTOM_GAP_DP)
        }

        root.addView(holder, params)
        barContainer = holder
        liquidTabBar = bar

        // Recalculate the dock width if the window size changes (tablet,
        // rotation, split-screen, foldable). Width is capped so the tabs never
        // become comically stretched on a large display.
        root.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            val newWidth = right - left
            val oldWidth = oldRight - oldLeft
            if (newWidth <= 0 || newWidth == oldWidth) return@addOnLayoutChangeListener
            val lp = holder.layoutParams as? FrameLayout.LayoutParams ?: return@addOnLayoutChangeListener
            val wanted = calculateBarWidthPx(newWidth)
            if (lp.width != wanted) {
                lp.width = wanted
                lp.gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
                lp.leftMargin = 0
                lp.rightMargin = 0
                holder.layoutParams = lp
                holder.post {
                    holder.pivotX = holder.width / 2f
                    holder.pivotY = holder.height / 2f
                }
            }
        }

        // Apply real navigation/gesture inset so the dock never sits on top of
        // the Android home gesture area.
        ViewCompat.setOnApplyWindowInsetsListener(holder) { _, insets ->
            val navBottom = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            val lp = holder.layoutParams as FrameLayout.LayoutParams
            val wanted = navBottom + dp(BAR_BOTTOM_GAP_DP)
            if (lp.bottomMargin != wanted) {
                lp.bottomMargin = wanted
                holder.layoutParams = lp
            }
            insets
        }
        ViewCompat.requestApplyInsets(holder)

        bar.post {
            // Scale from the exact visual center. This is intentional: compact
            // mode must not pull the bar toward the right on RTL layouts.
            holder.pivotX = holder.width / 2f
            holder.pivotY = holder.height / 2f
            // Child itself stays at scale 1; only the centered holder scales.
            bar.scaleX = 1f
            bar.scaleY = 1f
            // Re-resolve in case FlutterView was attached one frame later.
            if (flutterBackdrop == null) {
                flutterBackdrop = findFlutterView(root)
                flutterBackdrop?.let { bar.backdropSource = it }
            }
            applySelectedIndex(pendingIndex)
            applyAppTypeface(appliedFontFamily ?: "Monadi", force = true)
            animateBarScale(immediate = true)
            applyBarVisibility(pendingVisible, immediate = true)
            bar.invalidate()
        }
    }

    private fun applySelectedIndex(index: Int) {
        val bar = liquidTabBar ?: return
        val safe = index.coerceIn(0, 4)
        val nativeIndex = 4 - safe
        if (bar.selectedIndex == nativeIndex) return
        syncingFromFlutter = true
        try {
            // The library performs its own liquid stretch + overshoot animation.
            bar.selectedIndex = nativeIndex
        } finally {
            syncingFromFlutter = false
        }
    }

    private fun animateBarScale(immediate: Boolean = false) {
        val holder = barContainer ?: return
        // 15% compact while scrolling down. A touch still adds the requested
        // subtle 0.5% breathing response without using View.animate(), because
        // the library also owns internal motion on this same View.
        val compactScale = if (pendingCompact) 0.85f else 1f
        val pressScale = if (touchingBar) 1.005f else 1f
        val target = compactScale * pressScale

        scaleAnimator?.cancel()
        if (immediate) {
            holder.pivotX = holder.width / 2f
            holder.pivotY = holder.height / 2f
            holder.scaleX = target
            holder.scaleY = target
            return
        }

        holder.pivotX = holder.width / 2f
        holder.pivotY = holder.height / 2f
        val from = holder.scaleX
        scaleAnimator = ValueAnimator.ofFloat(from, target).apply {
            duration = ANIMATION_MS
            interpolator = DecelerateInterpolator(1.45f)
            addUpdateListener { animator ->
                val value = animator.animatedValue as Float
                holder.scaleX = value
                holder.scaleY = value
            }
            start()
        }
    }

    private fun applyBarVisibility(visible: Boolean, immediate: Boolean = false) {
        val bar = barContainer ?: return

        // Flutter rebuilds the shell frequently while scrolling. Re-applying
        // "visible=true" used to restart an alpha/translation animation on
        // every sync, which looked like the dock blinking downward. Ignore
        // repeated state completely.
        if (!immediate && appliedVisible == visible) return
        appliedVisible = visible

        if (immediate) {
            bar.animate().cancel()
            bar.visibility = if (visible) View.VISIBLE else View.GONE
            bar.alpha = if (visible) 1f else 0f
            bar.translationY = 0f
            return
        }

        bar.animate().cancel()
        if (visible) {
            bar.visibility = View.VISIBLE
            bar.translationY = 0f
            bar.animate()
                .alpha(1f)
                .setDuration(220L)
                .setInterpolator(DecelerateInterpolator())
                .start()
        } else {
            bar.animate()
                .alpha(0f)
                .setDuration(160L)
                .setInterpolator(android.view.animation.AccelerateInterpolator())
                .setListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        bar.visibility = View.GONE
                        bar.translationY = 0f
                        bar.animate().setListener(null)
                    }
                })
                .start()
        }
    }

    private fun applyAppTypeface(family: String, force: Boolean = false) {
        val bar = liquidTabBar ?: run {
            appliedFontFamily = family
            return
        }
        if (!force && appliedFontFamily == family) return
        appliedFontFamily = family

        val candidates = listOf(
            "flutter_assets/assets/fonts/$family.ttf",
            "flutter_assets/assets/fonts/$family.otf",
            "flutter_assets/assets/fonts/Monadi.ttf"
        )
        val typeface = candidates.firstNotNullOfOrNull { path ->
            try { Typeface.createFromAsset(assets, path) } catch (_: Throwable) { null }
        } ?: return

        applyTypefaceRecursively(bar, typeface)
        // The tab bar may create its label children during its next layout pass.
        bar.post { applyTypefaceRecursively(bar, typeface) }
    }

    private fun applyTypefaceRecursively(view: View, typeface: Typeface) {
        if (view is TextView) view.typeface = typeface
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                applyTypefaceRecursively(view.getChildAt(i), typeface)
            }
        }
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findFlutterView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun calculateBarWidthPx(availableWidthPx: Int): Int {
        val density = resources.displayMetrics.density
        val safeAvailable = if (availableWidthPx > 0) {
            availableWidthPx
        } else {
            resources.displayMetrics.widthPixels
        }
        val widthDp = safeAvailable / density
        val sidePaddingPx = dp(BAR_SIDE_MARGIN_DP) * 2
        val availableAfterPadding = (safeAvailable - sidePaddingPx).coerceAtLeast(dp(280))

        // Phones: familiar compact dock, up to 430dp.
        // Tablets / wide windows: grow modestly for comfortable spacing, but
        // cap at 560dp so the four tabs remain visually grouped at center.
        val maxWidthDp = if (widthDp >= TABLET_BREAKPOINT_DP) {
            TABLET_MAX_BAR_WIDTH_DP
        } else {
            PHONE_MAX_BAR_WIDTH_DP
        }

        // On narrow phones use almost the full usable width. On tablets allow
        // roughly 72% of the window until the max cap is reached.
        val target = if (widthDp >= TABLET_BREAKPOINT_DP) {
            (safeAvailable * 0.72f).toInt()
        } else {
            availableAfterPadding
        }
        return target.coerceAtMost(dp(maxWidthDp)).coerceAtMost(availableAfterPadding)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + 0.5f).toInt()

    private fun dpF(value: Float): Float = value * resources.displayMetrics.density
}
