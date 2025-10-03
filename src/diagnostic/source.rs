#[derive(Clone, Debug)]
pub struct Source {}

#[derive(Clone, Debug)]
pub struct Sources {
    sources: Vec<Source>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SourceId {
    index: u32,
}

impl SourceId {
    pub const fn index(self) -> u32 {
        self.index
    }
}
