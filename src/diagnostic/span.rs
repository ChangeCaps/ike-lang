use crate::diagnostic::SourceId;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Span {
    pub source: SourceId,
    pub start:  u32,
    pub end:    u32,
}

impl Span {
    pub const fn new(source: SourceId, start: u32, end: u32) -> Self {
        Self { source, start, end }
    }

    pub fn join(self, other: Self) -> Self {
        assert_eq!(self.source, other.source);

        Self {
            source: self.source,
            start:  self.start.min(other.start),
            end:    self.end.max(other.end),
        }
    }
}
