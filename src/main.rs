use std::{error::Error, fs};

use ike::{diagnostic::SourceId, lower};

fn main() -> Result<(), Box<dyn Error>> {
    let mut emitter = Vec::new();

    let input = fs::read_to_string("test.ike")?;
    let ast = ike::parse::parse_file(&mut emitter, &input, SourceId::DUMMY);

    let mut lowerer = lower::Lowerer::new(&mut emitter);
    lowerer.add_file(&["test"], &ast);

    let unit = lowerer.finish();

    for diagnostic in emitter {
        println!("{diagnostic:?}");
    }

    //println!("{unit:#?}");

    Ok(())
}
