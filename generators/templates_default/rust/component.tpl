//! Component: {{component_name}}
//!
//! {{description}}
{{acceptance_criteria}}
use serde::{Deserialize, Serialize};
use std::any::Any;
{{imports_block}}
/// {{description}}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct {{component_name}} {
{{struct_fields}}
    pub optional: bool,
}

pub const NAME: &str = "{{component_name}}";
{{exports_const_line}}
{{todos_block}}
impl {{component_name}} {
    pub fn new() -> Self {
        Self {
{{struct_field_inits}}
            optional: {{optional_rust}},
        }
    }

    /// 执行 {{component_name}} 的核心逻辑
    pub fn call(&self) -> Box<dyn Any> {
        unimplemented!("{{component_name}}::call() 待实现")
    }
}

impl Default for {{component_name}} {
    fn default() -> Self { Self::new() }
}
