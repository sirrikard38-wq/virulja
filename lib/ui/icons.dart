import 'package:web/web.dart' as web;

import 'dom.dart';

/// Line icons in a 24 x 24 drawing.
const Map<String, List<String>> _icons = {
  'back': ['M19 12H5', 'M11 6l-6 6 6 6'],
  'tool': [
    'M11 9.5l5.6-5.6a2.1 2.1 0 0 1 3 0l.5.5a2.1 2.1 0 0 1 0 3L14.5 13z',
    'M15 8l2.5-2.5',
    'M12.7 11.3l-6.2 6.2',
    'M5.5 16.5l2 2-3.5 2.5-1-1z',
  ],
  'plus': ['M12 5v14', 'M5 12h14'],
  'close': ['M6 6l12 12', 'M18 6L6 18'],
  'send': ['M5 12h14', 'M13 6l6 6-6 6'],
  'compass': ['M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0', 'M15.5 8.5l-2 5-5 2 2-5z'],
  'photo': [
    'M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
    'M7 10a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0',
    'M3 17l5-4 4 3 3-2 6 4',
  ],
  'group': [
    'M5.5 8a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0',
    'M3 20c0-3.5 2.7-6 6-6s6 2.5 6 6',
    'M16 5a3.5 3.5 0 0 1 0 6.5',
    'M18 14.5c2 .8 3 2.8 3 5.5',
  ],
  'sound': ['M4 10v4h3.5L12 18V6L7.5 10H4z', 'M15.5 9.5a3.5 3.5 0 0 1 0 5', 'M18 7a7 7 0 0 1 0 10'],
  'muted': ['M4 10v4h3.5L12 18V6L7.5 10H4z', 'M16 9.5l5 5', 'M21 9.5l-5 5'],
  'note': [
    'M9 18V6l10-2v12',
    'M4 18a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0',
    'M14 16a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0',
  ],
  'play': ['M8 5v14l11-7z'],
  'thumb': [
    'M7 11v9H4v-9z',
    'M7 11l4-7a2 2 0 0 1 2 2v4h6a2 2 0 0 1 2 2.300l-1.200 6A2 2 0 0 1 17.800 20H7',
  ],
  'comment': ['M4 5h16v11H9l-5 4z'],
  'link': ['M14 4h6v6', 'M20 4l-9 9', 'M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5'],
  'heart': ['M12 20s-7-4.400-7-10a4 4 0 0 1 7-2.600A4 4 0 0 1 19 10c0 5.600-7 10-7 10z'],
  'laugh': [
    'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0',
    'M8 14c1 2 2.400 3 4 3s3-1 4-3',
    'M8.500 9.500h.01',
    'M15.500 9.500h.01',
  ],
  'cheers': ['M7 3h10l-.6 6a4.400 4.400 0 0 1-8.800 0z', 'M12 13.500V20', 'M8.500 20h7'],
  'sun': [
    'M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0',
    'M12 3v2',
    'M12 19v2',
    'M3 12h2',
    'M19 12h2',
    'M5.600 5.600L7 7',
    'M17 17l1.400 1.400',
    'M5.600 18.400L7 17',
    'M17 7l1.400-1.400',
  ],
  'star': ['M12 4l2.400 5 5.600.8-4 3.900 1 5.500-5-2.600-5 2.600 1-5.500-4-3.900 5.600-.8z'],
};

/// A line icon; it takes its colour from the text around it.
web.Element icon(String name, {int size = 24}) => svg(
      'svg',
      cls: 'icon',
      attrs: {
        'viewBox': '0 0 24 24',
        'width': '$size',
        'height': '$size',
        'aria-hidden': 'true',
      },
      children: [
        for (final path in _icons[name]!) svg('path', attrs: {'d': path}),
      ],
    );

/// The spiral of the logo (temporary, see tool/make_icons.ps1).
web.Element logoMark({int size = 36}) => svg(
      'svg',
      cls: 'brand-mark',
      attrs: {
        'viewBox': '0 0 64 64',
        'width': '$size',
        'height': '$size',
        'aria-hidden': 'true',
      },
      children: [
        svg('path', attrs: {
          'd': 'M32 32a4 4 0 0 1 8 0a8 8 0 0 1-16 0a12 12 0 0 1 24 0'
              'a16 16 0 0 1-32 0a20 20 0 0 1 40 0a24 24 0 0 1-48 0',
          'fill': 'none',
          'stroke': 'currentColor',
          'stroke-width': '4',
          'stroke-linecap': 'round',
        }),
      ],
    );
