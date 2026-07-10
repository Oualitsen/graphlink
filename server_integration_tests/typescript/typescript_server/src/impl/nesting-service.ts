import { NestingService } from '../generated/services/nesting-service.js';
import { Color } from '../generated/enums/color.js';
import { Box } from '../generated/types/box.js';
import { Circle } from '../generated/types/circle.js';
import { Square } from '../generated/types/square.js';
import { Photo } from '../generated/types/photo.js';
import { Video } from '../generated/types/video.js';
import { Shape } from '../generated/interfaces/shape.js';
import { Media } from '../generated/interfaces/media.js';

/** List-depth (1/2/3) × nullability × kind (type / interface / union / enum) resolvers. */
export class NestingServiceImpl implements NestingService {
  private box = (id: string): Box => ({ id, label: `label-${id}` });
  private circle = (id: string): Circle => ({ __typename: 'Circle', id, kind: 'circle', radius: 1 });
  private square = (id: string): Square => ({ __typename: 'Square', id, kind: 'square', side: 2 });
  private photo = (id: string): Photo => ({ __typename: 'Photo', id, url: `https://x/${id}.jpg`, width: 640 });
  private video = (id: string): Video => ({ __typename: 'Video', id, url: `https://x/${id}.mp4`, durationSec: 30 });

  async colors1(): Promise<Color[]> {
    return [Color.Red, Color.Green, Color.Blue];
  }

  async colors2(): Promise<((Color | null)[] | null)[] | null> {
    return [[Color.Red], [Color.Green, Color.Blue]];
  }

  async colors3(): Promise<Color[][][]> {
    return [[[Color.Red]]];
  }

  async boxes1(): Promise<(Box | null)[] | null> {
    return [this.box('b1'), this.box('b2')];
  }

  async boxes2(): Promise<Box[][]> {
    return [[this.box('b1')], [this.box('b2')]];
  }

  async boxes3(): Promise<(((Box | null)[] | null)[] | null)[] | null> {
    return [[[this.box('b1')]]];
  }

  async shapes1(): Promise<Shape[]> {
    return [this.circle('c1'), this.square('s1')];
  }

  async shapes2(): Promise<((Shape | null)[] | null)[] | null> {
    return [[this.circle('c1')], [this.square('s1')]];
  }

  async shapes3(): Promise<Shape[][][]> {
    return [[[this.circle('c1'), this.square('s1')]]];
  }

  async media1(): Promise<Media[]> {
    return [this.photo('p1'), this.video('v1')];
  }

  async media2(): Promise<((Media | null)[] | null)[] | null> {
    return [[this.photo('p1')], [this.video('v1')]];
  }

  async media3(): Promise<Media[][][]> {
    return [[[this.photo('p1'), this.video('v1')]]];
  }
}
