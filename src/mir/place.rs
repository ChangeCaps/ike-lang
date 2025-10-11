#[derive(Clone, Debug)]
pub struct Place {
    pub kind: PlaceKind,
    pub proj: Vec<Projection>,
}

impl Place {
    pub fn argument(index: usize) -> Self {
        Self {
            kind: PlaceKind::Argument(index),
            proj: Vec::new(),
        }
    }

    pub fn local(index: usize) -> Self {
        Self {
            kind: PlaceKind::Local(index),
            proj: Vec::new(),
        }
    }
}

#[derive(Clone, Debug)]
pub enum PlaceKind {
    Argument(usize),
    Local(usize),
}

#[derive(Clone, Debug)]
pub enum Projection {
    Field(usize),
}
