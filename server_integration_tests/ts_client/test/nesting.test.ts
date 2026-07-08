import { describe, test, expect } from 'vitest';
import { Color } from '../src/generated/enums/color.js';
import type { Photo } from '../src/generated/types/photo.js';
import type { Video } from '../src/generated/types/video.js';
import { newClient } from './fixtures.js';

describe('nesting', () => {
  const client = newClient();

  test('enum list depths 1 / 2 / 3', async () => {
    expect((await client.queries.colors1()).colors1).toEqual([Color.Red, Color.Green, Color.Blue]);
    expect((await client.queries.colors2()).colors2).toEqual([
      [Color.Red],
      [Color.Green, Color.Blue],
    ]);
    expect((await client.queries.colors3()).colors3).toEqual([
      [[Color.Red]],
    ]);
  });

  test('type list depths 1 / 2 / 3', async () => {
    const b1 = (await client.queries.boxes1()).boxes1;
    expect(b1).toHaveLength(2);

    const b2 = (await client.queries.boxes2()).boxes2;
    expect(b2).toHaveLength(2);

    const b3 = (await client.queries.boxes3()).boxes3;
    expect(b3![0]![0]![0]!.id).toBe('b1');
  });

  test('interface list depths 1 / 2 / 3', async () => {
    const s1 = (await client.queries.shapes1()).shapes1;
    expect(s1.map(s => s.kind)).toEqual(expect.arrayContaining(['circle', 'square']));

    const s3 = (await client.queries.shapes3()).shapes3;
    expect(s3[0][0][0].kind).not.toBeNull();
  });

  test('union list depths 1 / 2 / 3', async () => {
    const m1 = (await client.queries.media1()).media1;
    expect(m1).toHaveLength(2);
    // __typename resolves each member to its concrete type, and the per-member
    // inline fragment carries the distinct field.
    const photos = m1.filter((m): m is Photo => m.__typename === 'Photo');
    const videos = m1.filter((m): m is Video => m.__typename === 'Video');
    expect(photos[0].width).toBe(640);
    expect(videos[0].durationSec).toBe(30);

    const m3 = (await client.queries.media3()).media3;
    expect(m3[0][0][0].url).not.toBeNull();
  });
});
