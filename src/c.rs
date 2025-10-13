use crate::mir::{Body, Type, Unit};

struct Codegen<'a> {
    unit: &'a Unit,
}

impl Codegen<'_> {
    fn codegen_body(&mut self, body: &Body) {}

    fn codegen_type(&mut self, ty: &Type) -> String {
        match ty {
            Type::Num => String::from("ike_num"),
            Type::Str => String::from("ike_str"),
            Type::Bool => String::from("ike_bool"),
            Type::Never => String::from("void"),
            Type::List(_) => String::from(""),
            Type::Fn(items, _) => todo!(),
            Type::Record(items) => todo!(),
            Type::Union(items) => todo!(),
        }
    }
}
