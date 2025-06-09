#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Attrs {
    pub attrs: Vec<Attr>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Attr {
    pub name: String,
    pub value: String,
}
