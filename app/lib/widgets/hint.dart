import 'dart:async';

import 'package:flutter/material.dart';

/// 取代 Flutter 的 [Tooltip]。
///
/// Flutter 的 Tooltip 用 OverlayPortal 把提示「嫁接」到按鈕的 semantics 節點下；
/// 提示消失時引擎沒收到正確的更新，Windows 的無障礙橋接（AccessibilityBridge）
/// 會在之後的更新解參考空的父節點而崩潰（flutter/flutter#182444）。
/// 這裡改用一般 OverlayEntry 顯示，內容不產生任何 semantics 節點；
/// 提示文字以 Semantics.tooltip 掛在按鈕本身。
class Hint extends StatefulWidget {
  const Hint({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 500),
  });

  final String message;
  final Widget child;
  final Duration waitDuration;

  @override
  State<Hint> createState() => _HintState();
}

class _HintState extends State<Hint> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _timer;

  void _scheduleShow() {
    _timer?.cancel();
    if (widget.message.isEmpty) return;
    _timer = Timer(widget.waitDuration, _show);
  }

  void _show() {
    if (!mounted || _entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final theme = Theme.of(context);
    final below = _isUpperHalf();
    _entry = OverlayEntry(
      builder: (_) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: below ? Alignment.bottomCenter : Alignment.topCenter,
          followerAnchor: below ? Alignment.topCenter : Alignment.bottomCenter,
          offset: Offset(0, below ? 6 : -6),
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface.withValues(
                      alpha: 0.92,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  bool _isUpperHalf() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return true;
    final y = box.localToGlobal(box.size.center(Offset.zero)).dy;
    return y < MediaQuery.sizeOf(context).height * 0.6;
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void didUpdateWidget(covariant Hint old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) _hide();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      tooltip: widget.message.isEmpty ? null : widget.message,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _scheduleShow(),
          onExit: (_) => _hide(),
          child: Listener(onPointerDown: (_) => _hide(), child: widget.child),
        ),
      ),
    );
  }
}
