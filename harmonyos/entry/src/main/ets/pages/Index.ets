import { ArchiveRoot } from '../ui/ArchiveRoot';

@Entry
@ComponentV2
struct Index {
  build() {
    Stack() {
      ArchiveRoot()
    }
    .width('100%')
    .height('100%')
  }
}
