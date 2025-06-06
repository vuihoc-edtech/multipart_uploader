enum PartStatus { notStarted, inProgress, completed, failed }

enum UploaderStatus { idle, uploading, completed, failed }

enum SectionType {
  video(8),
  image(9);

  final num value;

  const SectionType(this.value);
}
