from asyncua import Client, Node, ua
import asyncio
import os
import logging
from dotenv import load_dotenv

_logger_opcua = logging.getLogger("asyncua")

COUNT = 0
CONNECT_SUCCESS = False
CLIENT: Client

load_dotenv()

class GatewayCopy:
    def __init__(self):
        self.temp = -255

GATEWAY_COPY = GatewayCopy()

class SubscriptionHandler:
    def datachange_notification(self, node: Node, val, data):
        """
        Implement SubscriptionHandler trait, callback for data change of any node
        """
        GATEWAY_COPY.temp = val
        _logger_opcua.warn(f"Node {node} data changed to {val}")


async def task():
    global COUNT
    global CONNECT_SUCCESS
    global CLIENT

    url: str = os.getenv('OPCUA_SERVER_URL')
    usr: str = os.getenv('OPCUA_USR')
    pwd: str = os.getenv('OPCUA_PWD')

    if COUNT == 0:
        try:
            COUNT = COUNT + 1
            CLIENT = Client(url=url)
            CLIENT.set_user(usr)
            CLIENT.set_password(pwd)
            _logger_opcua.warn("Connecting to OPC UA server...")
            await CLIENT.connect()

            CONNECT_SUCCESS = True
        except Exception as e:
            COUNT = 0
            CONNECT_SUCCESS = False
            _logger_opcua.error(f"Failed to connect: {e}")

    if COUNT != 0 and CONNECT_SUCCESS:
        try:
            idx = await CLIENT.get_namespace_index(uri="urn:GipopPlcServer")
            parent = await CLIENT.nodes.objects.get_child(ua.QualifiedName(Name="PlcTags"))
            # nodes = await parent.get_children()
            temp_node = await parent.get_child(ua.QualifiedName(Name="temperature"))
            
            handler = SubscriptionHandler()
            subscription = await CLIENT.create_subscription(500, handler)
            await subscription.subscribe_data_change(temp_node)

            # GATEWAY_COPY.temp = await client.read_values([temp_node])[0]

        except Exception:
            _logger_opcua.exception("error")
            
async def client_main():
    await task()
    await asyncio.sleep(0.2)