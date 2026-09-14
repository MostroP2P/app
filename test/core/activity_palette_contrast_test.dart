import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/order_book_palette.dart';

import 'order_book_palette_contrast_test.dart' show contrastRatio, flatten;

const _aa = 4.5;

void _expectAA(String label, Color fg, Color bg) {
  final ratio = contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label: ${ratio.toStringAsFixed(2)}:1 < $_aa:1',
  );
}

/// Every text role of the trades and chat tabs against the surface it really
/// renders on. Translucent chip, segment and avatar fills are flattened over
/// that surface first.
void main() {
  for (final (mode, pal, book) in [
    ('dark', ActivityPalette.dark, OrderBookPalette.dark),
    ('light', ActivityPalette.light, OrderBookPalette.light),
  ]) {
    group('ActivityPalette.$mode contrast', () {
      final page = book.bg;
      final card = book.surface;

      test('group headers sit on the page', () {
        _expectAA('group header', pal.groupHeader, page);
      });

      test('trade card text', () {
        _expectAA('direction', book.textStrong, card);
        _expectAA('counterparty', book.textTertiary, card);
        _expectAA('time', book.textFaint, card);
        _expectAA('amount', book.textPrimary, card);
        _expectAA('sats', book.textMuted, card);
        _expectAA('payment method', book.textTertiary, card);
        _expectAA('action verb', book.limeInk, card);
      });

      test('status chips over their own fill on a card', () {
        _expectAA(
          'your turn',
          pal.chipActionInk,
          flatten(pal.chipActionBg, card),
        );
        _expectAA('waiting', pal.chipWaitInk, flatten(pal.chipWaitBg, card));
        _expectAA('done', pal.chipDoneInk, flatten(pal.chipDoneBg, card));
        _expectAA(
          'dispute',
          pal.chipDisputeInk,
          flatten(pal.chipDisputeBg, card),
        );
      });

      test('header controls on the page', () {
        _expectAA('filter', book.textMuted, flatten(pal.filterBg, page));
        _expectAA(
          'filter applied',
          pal.chipActionInk,
          flatten(pal.chipActionBg, page),
        );
        _expectAA(
          'segment selected',
          pal.chipActionInk,
          flatten(pal.chipActionBg, page),
        );
        _expectAA('segment idle', book.textMuted, flatten(pal.segIdleBg, page));
      });

      test('counters', () {
        _expectAA('badge', pal.badgeInk, pal.badgeBg);
      });

      test('conversation rows', () {
        _expectAA(
          'avatar active',
          pal.chipActionInk,
          flatten(pal.avatarActiveBg, card),
        );
        _expectAA(
          'avatar waiting',
          pal.chipWaitInk,
          flatten(pal.avatarWaitBg, card),
        );
        _expectAA(
          'avatar closed',
          pal.avatarClosedInk,
          flatten(pal.avatarClosedBg, card),
        );
        _expectAA('alias', book.textPrimary, card);
        _expectAA('context', book.textTertiary, card);
        _expectAA('last message unread', book.textStrong, card);
        _expectAA('last message read', book.textSecondary, card);
        _expectAA('time unread', book.limeIcon, card);
      });
    });
  }
}
