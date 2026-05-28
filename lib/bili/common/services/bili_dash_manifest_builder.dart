import '../models/bili_models.dart';

final class BiliDashManifestBuilder {
  const BiliDashManifestBuilder();

  String build(BiliDashManifestData manifestData) {
    final durationSeconds = (manifestData.durationMs / 1000).toStringAsFixed(3);
    final minBufferSeconds = (manifestData.minBufferTimeMs / 1000)
        .toStringAsFixed(3);

    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
        'type="static" '
        'profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" '
        'mediaPresentationDuration="PT${durationSeconds}S" '
        'minBufferTime="PT${minBufferSeconds}S">',
      )
      ..writeln('  <Period duration="PT${durationSeconds}S">');

    if (manifestData.videoStreams.isNotEmpty) {
      buffer.writeln(
        '    <AdaptationSet id="0" contentType="video" mimeType="video/mp4" '
        'segmentAlignment="true" startWithSAP="1" subsegmentAlignment="true">',
      );
      for (final stream in manifestData.videoStreams) {
        buffer.writeln(_representationXml(stream, indent: '      '));
      }
      buffer.writeln('    </AdaptationSet>');
    }

    if (manifestData.audioStreams.isNotEmpty) {
      buffer.writeln(
        '    <AdaptationSet id="1" contentType="audio" mimeType="audio/mp4" '
        'segmentAlignment="true" startWithSAP="1" '
        'subsegmentAlignment="true" lang="und">',
      );
      for (final stream in manifestData.audioStreams) {
        buffer.writeln(_representationXml(stream, indent: '      '));
      }
      buffer.writeln('    </AdaptationSet>');
    }

    buffer
      ..writeln('  </Period>')
      ..write('</MPD>');

    return buffer.toString();
  }

  String _representationXml(BiliDashStream stream, {required String indent}) {
    final baseUrls = <String>[];
    final seenBaseUrls = <String>{};
    for (final url in <String>[stream.baseUrl, ...stream.backupUrls]) {
      if (url.isNotEmpty && seenBaseUrls.add(url)) {
        baseUrls.add(url);
      }
    }
    final attributes = <String>[
      'id="${_xmlEscape(stream.representationId ?? '${stream.id}')}"',
      'bandwidth="${stream.bandwidth}"',
      'codecs="${_xmlEscape(stream.codecs)}"',
    ];

    if (stream.width != null) {
      attributes.add('width="${stream.width}"');
    }
    if (stream.height != null) {
      attributes.add('height="${stream.height}"');
    }
    if (stream.frameRate != null && stream.frameRate!.isNotEmpty) {
      attributes.add('frameRate="${stream.frameRate}"');
    }
    if (stream.audioSamplingRate != null &&
        stream.audioSamplingRate!.isNotEmpty) {
      attributes.add('audioSamplingRate="${stream.audioSamplingRate}"');
    }
    if (stream.startWithSap != null) {
      attributes.add('startWithSAP="${stream.startWithSap}"');
    }

    final baseUrlXml = baseUrls
        .map((url) => '<BaseURL>${_xmlEscape(url)}</BaseURL>')
        .join();

    return '$indent<Representation ${attributes.join(' ')}>'
        '$baseUrlXml'
        '<SegmentBase indexRange="${stream.segmentInfo.indexRange}">'
        '<Initialization range="${stream.segmentInfo.initialization}" />'
        '</SegmentBase>'
        '</Representation>';
  }

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
