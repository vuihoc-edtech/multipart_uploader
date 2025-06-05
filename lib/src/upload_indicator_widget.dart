import 'package:flutter/material.dart';
import 'package:multipart_uploader/multipart_uploader.dart';
import 'package:multipart_uploader/src/model/upload_part.dart';

class UploadIndicatorWidget extends StatelessWidget {
  final List<UploadPart> parts;
  final int fileSize;
  final double? width;
  final double height;
  final Color backgroundColor;
  final Color progressColor;
  final BorderRadius? borderRadius;

  const UploadIndicatorWidget({
    super.key,
    required this.parts,
    required this.fileSize,
    this.width,
    this.height = 10,
    this.backgroundColor = const Color(0x42000000), // Colors.black26
    this.progressColor = Colors.green,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final indicatorWidth = width ?? constraints.maxWidth;

          return ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.circular(3),
            child: Container(
              width: indicatorWidth,
              height: height,
              color: backgroundColor,
              child: Row(
                children: parts.map((part) {
                  final partWidth = (part.length / fileSize * indicatorWidth)
                      .clamp(0, indicatorWidth)
                      .toDouble();

                  return Container(
                    width: partWidth,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: (part.uploadedBytes / part.length * partWidth)
                          .clamp(0, partWidth),
                      decoration: BoxDecoration(
                        color: part.status == PartStatus.failed
                            ? Colors.redAccent
                            : progressColor,
                        // Border left color to indicate progress
                        border: Border(
                          left: part.uploadedBytes < part.length
                              ? BorderSide(color: progressColor, width: 1)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
