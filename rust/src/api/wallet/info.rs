use flutter_rust_bridge::frb;

use crate::api::structs::network::Network;

use super::SpWallet;

impl SpWallet {
    #[frb(sync)]
    pub fn get_receiving_address(&self) -> String {
        self.client
            .get_receiving_address()
            .to_display_for_network(self.client.sp_receiver.network)
            .to_string()
    }

    #[frb(sync)]
    pub fn get_change_address(&self) -> String {
        self.client
            .sp_receiver
            .get_change_address()
            .to_display_for_network(self.client.sp_receiver.network)
            .to_string()
    }

    #[frb(sync)]
    pub fn get_network(&self) -> Network {
        self.client.get_network().into()
    }
}
