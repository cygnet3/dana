use flutter_rust_bridge::frb;

pub enum FiatCurrency {
    Eur,
    Usd,
    Gbp,
    Cad,
    Chf,
    Aud,
    Jpy,
}

impl FiatCurrency {
    #[frb(sync)]
    pub fn symbol(&self) -> String {
        match self {
            Self::Eur => '€'.to_string(),
            Self::Usd => '$'.to_string(),
            Self::Gbp => '£'.to_string(),
            Self::Cad => '$'.to_string(),
            Self::Chf => "Fr.".to_string(),
            Self::Aud => "AU$".to_string(),
            Self::Jpy => '¥'.to_string(),
        }
    }

    #[frb(sync)]
    pub fn display_name(&self) -> String {
        match self {
            Self::Eur => "Euro",
            Self::Usd => "US Dollar",
            Self::Gbp => "Pound Sterling",
            Self::Cad => "Canadian Dollar",
            Self::Chf => "Swiss Franc",
            Self::Aud => "Australian Dollar",
            Self::Jpy => "Japanese Yen",
        }
        .to_string()
    }

    #[frb(sync)]
    pub fn minor_units(&self) -> u32 {
        match self {
            Self::Eur => 2,
            Self::Usd => 2,
            Self::Gbp => 2,
            Self::Cad => 2,
            Self::Chf => 2,
            Self::Aud => 2,
            Self::Jpy => 0,
        }
    }
}
