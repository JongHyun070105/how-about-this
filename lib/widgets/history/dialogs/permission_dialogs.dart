import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void _showStyledDialog({
  required BuildContext context,
  required String title,
  required String content,
  required List<Widget> actions,
  bool isError = false,
}) {
  final cupertinoActions = actions.map((widget) {
    if (widget is TextButton && widget.child is Text) {
      final textWidget = widget.child as Text;
      final isDestructive = textWidget.data == '설정으로 이동';

      return CupertinoDialogAction(
        onPressed: widget.onPressed,
        isDestructiveAction: isDestructive,
        child: Text(
          textWidget.data ?? '',
          style: TextStyle(
            fontFamily: 'Do Hyeon',
            fontWeight: isDestructive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }
    return widget;
  }).toList();

  showCupertinoDialog(
    context: context,
    builder: (BuildContext context) {
      return CupertinoAlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Do Hyeon',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Text(
            content,
            style: const TextStyle(fontFamily: 'Do Hyeon', fontSize: 16),
          ),
        ),
        actions: cupertinoActions,
      );
    },
  );
}

/// 사진 접근 권한 관련 다이얼로그
void showPhotoPermissionDialog(BuildContext context) {
  _showStyledDialog(
    context: context,
    title: '사진 접근 권한 필요',
    content:
        '리뷰에 사진을 첨부하기 위해 사진 접근 권한이 필요합니다.\n' // Corrected newline escape sequence
        '앱 설정에서 사진 권한을 허용해주세요.',
    isError: true,
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('나중에'),
      ),
      TextButton(
        onPressed: () {
          Navigator.of(context).pop();
          openAppSettings();
        },
        child: const Text('설정으로 이동'),
      ),
    ],
  );
}

void showFeatureRestrictedDialog(
  BuildContext context,
  String featureName,
  String message,
) {
  _showStyledDialog(
    context: context,
    title: '$featureName 사용 불가',
    content: message,
    isError: true,
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('확인'),
      ),
    ],
  );
}
