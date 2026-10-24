part of 'wardrive_screen.dart';

class _NodeStatsOverlay extends ConsumerWidget {
  const _NodeStatsOverlay({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final appState = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final selfId = AppState.canonicalNodeId(appState.nodeId);
    final nodeCount =
        appState.liveKnownNodes
            .where((id) => id != selfId && !appState.isManagerNode(id))
            .length;
    final showHeader = appState.isManagerConnected && appState.meshEnabled;
    final label = '$nodeCount NODE${nodeCount == 1 ? '' : 'S'}';
    final color =
        nodeCount > 0 ? AppTheme.success : AppTheme.warning;
    final perNode = <String, int>{...wd.detectionsPerNode};
    final selfRaw = wd.localWifiCount + wd.localBleCount;
    final selfScans = appState.isConnected && !appState.isManagerConnected;
    if (selfRaw > 0 || selfScans) {
      final selfBucket = appState.nodeId.isNotEmpty ? appState.nodeId : 'LOCAL';
      perNode[selfBucket] = (perNode[selfBucket] ?? 0) + selfRaw;
    }
    if (ref.watch(phoneBleSourceProvider).scanning) {
      perNode[BleManager.phoneNodeId] ??= 0;
    }
    final nodeEntries = perNode.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.85),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (nodeEntries.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...nodeEntries.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: e.key == 'LOCAL'
                              ? AppTheme.accent
                              : AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        '${appState.labelForNode(e.key)}: ${e.value}',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 9,
                          fontFamily: AppTheme.mono,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _CurrentPosMarker extends StatelessWidget {
  const _CurrentPosMarker();

  @override
  Widget build(BuildContext context) => Center(
        child: CustomPaint(
          size: const Size(14, 14),
          painter: _DotPainter(color: AppTheme.accent),
        ),
      );
}

class _DotPainter extends CustomPainter {
  const _DotPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c, size.width / 2 + 1.5,
      Paint()..color = color.withValues(alpha: 0.25),
    );
    canvas.drawCircle(c, size.width / 2, Paint()..color = color);
    canvas.drawCircle(
      c, size.width / 2 - 1.2,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.drawCircle(c, 2.4, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant _DotPainter old) => old.color != color;
}
