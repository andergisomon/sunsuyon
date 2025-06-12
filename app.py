import opcua_client
import supabase
import os
import asyncio
import logging
from dotenv import load_dotenv

logging.basicConfig(level=logging.WARN)
_logger = logging.getLogger("supabase")

SB: supabase.Client

load_dotenv()

ACCESS_TOKEN: str = "uninitialized"

def init_supabase() -> (bool, supabase.Client):
    url: str = os.getenv('SUPABASE_URL')
    key: str = os.getenv('SUPABASE_KEY')
    SB = supabase.create_client(url, key)

    email: str = os.getenv('WRITER_EMAIL')
    pwd: str = os.getenv('WRITER_PWD')

    res = SB.auth.sign_in_with_password(
        {
            "email": email,
            "password": pwd
        }
    )

    ACCESS_TOKEN = res.session.access_token

    # verify creds by asking server again
    res = SB.auth.get_user()
    checked_usr_id = res.user.id
    checked_usr_role = res.user.role

    # check session stored in local memory
    res = SB.auth.get_session()
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
        return (True, SB)

async def main(client):
    # app logic here
    try:
        val = opcua_client.GATEWAY_COPY.temp
        _logger.warn(f"Appending table with value {val}")
        res = (
            client.table("temperature")
            .insert({"temp": val})
            .execute()
        )

    except Exception as e:
        _logger.error(f"Failed to append table: {e}")
    
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
        _logger.info("Authentication with Supabase successful")
        asyncio.run(init_app(client))
    else:
        _logger.error("Authentication with Supabase failed")