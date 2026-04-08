/// IndexedDB storage backend — WASM target only.
///
/// Full implementation is deferred to Phase 3. This stub satisfies the
/// Storage trait so that the WASM build compiles during Phase 2.
use anyhow::{anyhow, Result};

use crate::api::types::{
    ChatMessage, IdentityInfo, OrderInfo, QueuedMessageStatus, RelayInfo, TradeInfo,
};
use crate::db::Storage;
use crate::queue::outbox::QueuedMessage;

pub struct IndexedDbStorage;

impl IndexedDbStorage {
    pub async fn open(_db_name: &str) -> Result<Self> {
        Ok(Self)
    }
}

impl Storage for IndexedDbStorage {
    async fn save_order(&self, _order: &OrderInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn get_order(&self, _id: &str) -> Result<Option<OrderInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_order(&self, _id: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_orders(&self) -> Result<Vec<OrderInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_trade(&self, _trade: &TradeInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn get_trade(&self, _id: &str) -> Result<Option<TradeInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_trades(&self) -> Result<Vec<TradeInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_message(&self, _msg: &ChatMessage) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_messages(&self, _trade_id: &str) -> Result<Vec<ChatMessage>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn mark_messages_read(&self, _trade_id: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_relay(&self, _relay: &RelayInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_relay(&self, _url: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_relays(&self) -> Result<Vec<RelayInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_identity(&self, _identity: &IdentityInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn get_identity(&self) -> Result<Option<IdentityInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_queued_message(&self, _msg: &QueuedMessage) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_queued_messages(&self) -> Result<Vec<QueuedMessage>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn update_queued_message_status(
        &self,
        _id: &str,
        _status: QueuedMessageStatus,
    ) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_queued_message(&self, _id: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }

    async fn save_trade_key(&self, _order_id: &str, _key_index: u32) -> Result<()> {
        Ok(()) // no-op: IndexedDB persistence not yet implemented
    }

    async fn get_trade_key(&self, _order_id: &str) -> Result<Option<u32>> {
        Ok(None) // no persisted key: caller will treat absence correctly
    }

    async fn save_mostro_node(&self, _node: &crate::api::types::MostroNodeInfo) -> Result<()> {
        log::warn!("save_mostro_node: IndexedDB backend not implemented — node selection will not survive reload");
        // TODO(#93): implement IndexedDB persistence for Mostro node selection
        Ok(())
    }

    async fn get_active_mostro_node(&self) -> Result<Option<crate::api::types::MostroNodeInfo>> {
        log::warn!("get_active_mostro_node: IndexedDB backend not implemented — falling back to default");
        // TODO(#93): implement IndexedDB persistence for Mostro node selection
        Ok(None)
    }

    async fn get_trade_by_order_id(
        &self,
        _order_id: &str,
    ) -> Result<Option<crate::api::types::TradeInfo>> {
        Ok(None) // no persisted trade: role lookup returns None
    }

    async fn update_trade_order_id(
        &self,
        _old_order_id: &str,
        _new_order_id: &str,
    ) -> Result<()> {
        Ok(()) // no-op: IndexedDB persistence not yet implemented
    }

    async fn update_trade_fields(
        &self,
        _order_id: &str,
        _status: Option<crate::api::types::OrderStatus>,
        _hold_invoice: Option<String>,
        _amount_sats: Option<u64>,
    ) -> Result<()> {
        Ok(()) // no-op: IndexedDB persistence not yet implemented
    }
}
