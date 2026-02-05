import 'package:flutter/material.dart';

class ListenableSelector<T> extends StatefulWidget {
  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
    this.shouldRebuild,
  });

  final Listenable listenable;
  final T Function() selector;
  final Widget Function(BuildContext context, T value) builder;
  final bool Function(T previous, T next)? shouldRebuild;

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.selector();
    widget.listenable.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(covariant ListenableSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
      _value = widget.selector();
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    final next = widget.selector();
    final shouldRebuild =
        widget.shouldRebuild?.call(_value, next) ?? _value != next;
    if (!shouldRebuild) {
      return;
    }
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _value);
  }
}
