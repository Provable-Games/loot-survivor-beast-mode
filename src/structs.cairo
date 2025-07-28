#[derive(Drop, Serde, Copy)]
pub struct LegacyBeast {
    pub id: u8,
    pub prefix: u8,
    pub suffix: u8,
    pub level: u16,
    pub health: u16,
}
