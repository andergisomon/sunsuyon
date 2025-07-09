from asyncua import Client, Node, ua
import asyncio
import os
import logging
from dotenv import load_dotenv
import datetime

_logger_opcua = logging.getLogger("asyncua")

COUNT = 0
CONNECT_SUCCESS = False
CLIENT: Client

load_dotenv()

class GatewayCopy:
    def __init__(self):
        self.temp = -255
        self.humd = -255
        self.area_1_lights = -255
        self.area_2_lights = -255
        self.area_1_lights_hmi_cmd = -255
        self.status = -255
        self.rmt_cmd_rag = 0
        self.rmt_cmd_area_2_lights = 0

GATEWAY_COPY = GatewayCopy()

class SubscriptionHandler:
    async def datachange_notification(self, node: Node, val, data):
        """
        Implement SubscriptionHandler trait, callback for data change of any node
        """
        browsename = await node.read_browse_name()
        match browsename.Name:
            case "temperature":
                GATEWAY_COPY.temp = val
            case "humidity":
                GATEWAY_COPY.humd = val
            case "area 1 lights":
                GATEWAY_COPY.area_1_lights = val
            case "area 2 lights":
                GATEWAY_COPY.area_2_lights = val
            case "area 1 lights hmi cmd":
                GATEWAY_COPY.area_1_lights_hmi_cmd = val
            case "status":
                GATEWAY_COPY.status = val
            case "remote cmd RAG tower lights":
                # Do nothing here, Sunsuyon will only fetch data from Supabase and write the value into the
                # corresponding OPC UA server tag, not the other way around
                # GATEWAY_COPY.rmt_cmd_rag = val
                ()
            case "remote cmd area 2 lights":
                # Do nothing here, Sunsuyon will only fetch data from Supabase and write the value into the
                # corresponding OPC UA server tag, not the other way around
                # GATEWAY_COPY.rmt_cmd_area_2_lights = val
                ()
            case _:
                _logger_opcua.error(f"Callback cannot find the node {browsename.Name}")

        _logger_opcua.info(f"Node {node} data changed to {val}")

async def task():
    global COUNT
    global CONNECT_SUCCESS
    global CLIENT

    url: str = os.getenv('OPCUA_SERVER_URL')
    usr: str = os.getenv('OPCUA_USR')
    pwd: str = os.getenv('OPCUA_PWD')

    if COUNT == 0:
        try:
            # Run once
            COUNT = COUNT + 1
            CLIENT = Client(url=url)
            CLIENT.set_user(usr)
            CLIENT.set_password(pwd)
            _logger_opcua.warning("Connecting to OPC UA server...")
            await CLIENT.connect()

            idx = await CLIENT.get_namespace_index(uri="urn:GipopPlcServer")
            parent = await CLIENT.nodes.objects.get_child(ua.QualifiedName(Name="PlcTags"))
            nodes = await parent.get_children()

            handler = SubscriptionHandler()
            subscription = await CLIENT.create_subscription(500, handler)

            await subscription.subscribe_data_change(nodes)

            CONNECT_SUCCESS = True
        except Exception as e:
            COUNT = 0
            CONNECT_SUCCESS = False
            _logger_opcua.error(f"Failed to connect: {e}")

    if COUNT != 0 and CONNECT_SUCCESS:
        try:
            # Reserve for operations that need to be run continuously 
            _logger_opcua.info(f"Writing remote command values from Supabase into OPC UA Server...")

            parent = await CLIENT.nodes.objects.get_child(ua.QualifiedName(Name="PlcTags"))
            nodes = await parent.get_children()

            for node in nodes:
                browse_name = await node.read_browse_name()
                match browse_name.Name:
                    case "remote cmd RAG tower lights":
                        rmt_cmd_rag_node = node
                    case "remote cmd area 2 lights":
                        rmt_cmd_area_2_lights_node = node
            
            # Wrapping the python type with ua.UInt32() is important, or else you'll get cryptic errors
            # and of course be sure to check the actual tag value type, in this case I know it's UInt32
            await rmt_cmd_rag_node.write_value(ua.UInt32(GATEWAY_COPY.rmt_cmd_rag))
            await rmt_cmd_area_2_lights_node.write_value(ua.UInt32(GATEWAY_COPY.rmt_cmd_area_2_lights))

        except Exception as e:
            # TODO: handle stopped server and other connection problems
            _logger_opcua.exception(f"error: {e}")
            
async def client_main():
    await task()
    await asyncio.sleep(0.2)