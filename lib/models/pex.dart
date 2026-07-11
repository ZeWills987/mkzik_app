import 'package:flutter/material.dart';

class PexTag {
  final String subtype;
  final String label;
  final IconData icon;
  const PexTag(this.subtype, this.label, this.icon);
}

const Map<String, PexTag> kPexTags = {
  'eight_d':   PexTag('eight_d',   '8D',       Icons.spatial_audio_off_rounded),
  'reverb':    PexTag('reverb',    'Reverb',   Icons.graphic_eq_rounded),
  'slowed':    PexTag('slowed',    'Slowed',   Icons.slow_motion_video_rounded),
  'spedup':    PexTag('spedup',    'Sped up',  Icons.fast_forward_rounded),
  'nightcore': PexTag('nightcore', 'Nightcore',Icons.nights_stay_rounded),
  'remix':     PexTag('remix',     'Remix',    Icons.tune_rounded),
  'edit':      PexTag('edit',      'Edit',     Icons.content_cut_rounded),
  'mashup':    PexTag('mashup',    'Mashup',   Icons.merge_rounded),
};

PexTag? pexTagFor(String? subtype) {
  if (subtype == null || subtype.isEmpty) return null;
  return kPexTags[subtype];
}
