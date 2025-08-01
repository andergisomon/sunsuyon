import opcua_client
import supabase
import os
import asyncio
import logging
from dotenv import load_dotenv

logging.basicConfig(level=logging.WARN)
_logger = logging.getLogger("supabase")

load_dotenv()

ACCESS_TOKEN: str = "uninitialized"

def init_supabase() -> (bool, supabase.Client):
    url: str = os.getenv('SUPABASE_URL')
    key: str = os.getenv('SUPABASE_KEY')
    sb = supabase.create_client(url, key)

    email: str = os.getenv('WRITER_EMAIL')
    pwd: str = os.getenv('WRITER_PWD')

    res = sb.auth.sign_in_with_password(
        {
            "email": email,
            "password": pwd
        }
    )

    ACCESS_TOKEN = res.session.access_token

    # verify creds by asking server again
    res = sb.auth.get_user()
    checked_usr_id = res.user.id
    checked_usr_role = res.user.role

    # check session stored in local memory
    res = sb.auth.get_session()
    signed_in_usr_id = res.user.id
    signed_in_usr_role = res.user.role

    # Guard creds against tampering
    if not (checked_usr_id == signed_in_usr_id and checked_usr_role == signed_in_usr_role == "authenticated"):
        # refuse login, end program
        _logger.error(f"""
        Access token obtained: {ACCESS_TOKEN}
        User ID from Server: {checked_usr_id}, User Role from Server: {checked_usr_role}
        Local User ID: {signed_in_usr_id}, Local User Role: {signed_in_usr_role}
        """)
        return (False, None)

    else:
        # proceed
        return (True, sb)

async def main(client):
    # app logic here
    try:
        val = opcua_client.GATEWAY_COPY
        # _logger.warn(f"Appending plc_tags table with value {val}")
        res = (
            client.table("plc_tags")
            .insert({
                "temperature": val.temp,
                "humidity": val.humd,
                "area_1_lights": val.area_1_lights,
                "area_2_lights": val.area_2_lights,
                "area_1_lights_hmi_cmd": val.area_1_lights_hmi_cmd,
                "status": val.status
            })
            .execute()
        )

    except Exception as e:
        _logger.error(f"Failed to append plc_tags table: {e}")
    
    try:
        _logger.warn("Fetching remote_cmd table")
        val = opcua_client.GATEWAY_COPY
        res = (
            client.table("remote_cmd")
            .select("*")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )

        val.rmt_cmd_rag = res.data[0]["rag"]
        _logger.warn(f"Fetched {val.rmt_cmd_rag}")
        val.rmt_cmd_area_2_lights = res.data[0]["lights"]
        _logger.warn(f"Fetched {val.rmt_cmd_area_2_lights}")

    except Exception as e:
        _logger.error(f"Failed to select remote_cmd table: {e}")
    
    await asyncio.sleep(0.5)


async def init_app(client):
    while True:
        await opcua_client.client_main()
        await main(client)

    _logger.info("app exited")

if __name__ == "__main__":
    # only start app if auth with supabase successful
    auth_status, client = init_supabase()
    if auth_status:
        _logger.warning("Authentication with Supabase successful")
        asyncio.run(init_app(client))
    else:
        _logger.error("Authentication with Supabase failed")