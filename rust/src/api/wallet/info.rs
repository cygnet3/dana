use flutter_rust_bridge::frb;

use crate::api::structs::network::Network;

use super::SpWallet;

impl SpWallet {
    #[frb(sync)]
    pub fn get_receiving_address(&self) -> String {
        self.client.receiving_code().to_string()
    }

    #[frb(sync)]
    pub fn get_change_address(&self) -> String {
        self.client.sp_receiver.receiving_code().to_string()
    }

    #[frb(sync)]
    pub fn get_network(&self) -> Network {
        self.client.network().into()
    }
}
