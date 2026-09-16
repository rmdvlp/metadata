import { describe, expect, it } from 'vitest';
import {
  formatCount,
  formatDelta,
  formatIsoDate,
  formatShortDate,
  formatTime,
  initials,
  percentChange,
  shortRef,
} from './format';

describe('date formatting', () => {
  const date = new Date(2026, 3, 21, 14, 3);

  it('matches the columns in the design', () => {
    expect(formatShortDate(date)).toBe('21 Apr');
    expect(formatTime(date)).toBe('02:03 PM');
    expect(formatIsoDate(date)).toBe('2026-04-21');
  });

  it('renders a missing timestamp as an em dash, not "Invalid Date"', () => {
    expect(formatShortDate(null)).toBe('—');
    expect(formatTime(undefined)).toBe('—');
    expect(formatIsoDate(null)).toBe('—');
  });

  it('zero-pads single-digit months and days', () => {
    expect(formatIsoDate(new Date(2026, 0, 5))).toBe('2026-01-05');
  });
});

describe('formatCount', () => {
  it('groups thousands', () => {
    expect(formatCount(234)).toBe('234');
    expect(formatCount(12_345)).toBe('12,345');
  });

  it('two-digit pads for the support tiles only', () => {
    expect(formatCount(3, true)).toBe('03');
    expect(formatCount(3)).toBe('3');
    expect(formatCount(30, true)).toBe('30');
  });
});

describe('percentChange', () => {
  it('rounds a normal change', () => {
    expect(percentChange(112, 100)).toBe(12);
    expect(percentChange(85, 100)).toBe(-15);
  });

  it('refuses to divide by a zero baseline', () => {
    expect(percentChange(5, 0)).toBeNull();
    expect(percentChange(0, 0)).toBe(0);
  });

  it('formats a delta two-digit padded, unsigned', () => {
    expect(formatDelta(12)).toBe('12%');
    expect(formatDelta(-3)).toBe('03%');
  });
});

describe('initials', () => {
  it('takes first and last', () => {
    expect(initials('Smith John')).toBe('SJ');
    expect(initials('Gustavo  Philips')).toBe('GP');
    expect(initials('Mary Jane Watson')).toBe('MW');
  });

  it('falls back on one word or none', () => {
    expect(initials('Aspen')).toBe('AS');
    expect(initials('   ')).toBe('?');
  });
});

describe('shortRef', () => {
  it('takes the last four characters, upper-cased', () => {
    expect(shortRef('7fKq2mXaB1cd')).toBe('#B1CD');
    expect(shortRef('7fKq2mXaB1cd', 'TK-')).toBe('TK-B1CD');
  });

  it('does not crash on an empty id', () => {
    expect(shortRef('')).toBe('#----');
  });
});
