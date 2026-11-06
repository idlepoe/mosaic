import 'dart:io';
import 'package:flutter/material.dart';
import 'models.dart';

class QueueThumbnail extends StatelessWidget {
  final QueueItem item;
  const QueueThumbnail({super.key, required this.item});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: 80,
      height: 64,
      child: ColoredBox(
        color: const Color(0xff111827),
        child: item.thumbnailLoading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : item.thumbnailPath == null
            ? const Center(
                child: Icon(Icons.movie_outlined, color: Colors.white54),
              )
            : Image.file(
                File(item.thumbnailPath!),
                fit: BoxFit.contain,
                cacheWidth: 256,
                errorBuilder: (_, error, stack) => const Center(
                  child: Icon(Icons.movie_outlined, color: Colors.white54),
                ),
              ),
      ),
    ),
  );
}
