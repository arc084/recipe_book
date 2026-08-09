import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

/// The extensions the app will take as a recipe photograph.
const _imageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'heic',
];

bool looksLikeImage(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1) return false;
  return _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Opens the platform's picker and gives the chosen image to [recipeId].
///
/// This is the phone's way in — dropping a file is a desktop gesture and means
/// nothing on Android, so the photo area is tappable there. It works on the
/// desktop too, for anyone who would rather browse than drag.
///
/// Returns true when a photo was set.
Future<bool> pickRecipePhoto(BuildContext context, String recipeId) async {
  const typeGroup = XTypeGroup(
    label: 'Images',
    extensions: _imageExtensions,
    // Android and iOS match on MIME rather than extension.
    mimeTypes: <String>['image/*'],
    uniformTypeIdentifiers: <String>['public.image'],
  );

  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
  if (file == null || !context.mounted) return false;

  await context.read<AppState>().adoptRecipePhoto(recipeId, file.path);
  return true;
}
