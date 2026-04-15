"""
AWS Lambda function to configure Cognito User Pool for Managed Login v2

This Lambda is invoked by Terraform after creating the User Pool and Domain.
It performs API calls that aren't available in the Terraform AWS provider:
1. Update domain to ManagedLoginVersion 2
2. Create Managed Login Branding

Environment Variables:
- USER_POOL_ID: Cognito User Pool ID
- APP_CLIENT_ID: Cognito App Client ID
- DOMAIN: Cognito domain prefix
- AWS_REGION: AWS region (automatically set by Lambda)
"""

import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

cognito = boto3.client('cognito-idp')

def lambda_handler(event, context):
    """
    Configure Cognito User Pool for Managed Login v2
    """

    user_pool_id = os.environ['USER_POOL_ID']
    app_client_id = os.environ['APP_CLIENT_ID']
    domain = os.environ['DOMAIN']
    region = os.environ['AWS_REGION']

    logger.info(f"Configuring Managed Login v2 for User Pool: {user_pool_id}")
    logger.info(f"Domain: {domain}")
    logger.info(f"App Client: {app_client_id}")

    results = {
        'user_pool_id': user_pool_id,
        'domain': domain,
        'app_client_id': app_client_id
    }

    # Step 1: Update domain to Managed Login Version 2
    try:
        logger.info("Step 1: Updating domain to Managed Login Version 2...")
        cognito.update_user_pool_domain(
            Domain=domain,
            UserPoolId=user_pool_id,
            ManagedLoginVersion=2
        )
        logger.info("✅ Domain updated to Managed Login v2")
        results['domain_update'] = 'success'
    except Exception as e:
        logger.error(f"❌ Failed to update domain: {str(e)}")
        results['domain_update'] = f'failed: {str(e)}'
        # Don't fail the Lambda if domain update fails

    # Step 2: Create Managed Login Branding
    try:
        logger.info("Step 2: Creating Managed Login Branding...")
        response = cognito.create_managed_login_branding(
            UserPoolId=user_pool_id,
            ClientId=app_client_id,
            UseCognitoProvidedValues=True
        )
        branding_id = response['ManagedLoginBranding']['ManagedLoginBrandingId']
        logger.info(f"✅ Managed Login Branding created: {branding_id}")
        results['branding_creation'] = 'success'
        results['branding_id'] = branding_id
    except cognito.exceptions.ManagedLoginBrandingExistsException:
        logger.info("ℹ️  Managed Login Branding already exists - skipping")
        results['branding_creation'] = 'already_exists'
    except Exception as e:
        logger.error(f"❌ Failed to create branding: {str(e)}")
        results['branding_creation'] = f'failed: {str(e)}'
        # Don't fail the Lambda if branding creation fails

    # Step 3: Verify configuration
    try:
        logger.info("Step 3: Verifying Managed Login Version...")
        response = cognito.describe_user_pool_domain(Domain=domain)
        version = response['DomainDescription'].get('ManagedLoginVersion', 1)
        results['managed_login_version'] = version

        if version == 2:
            logger.info(f"✅ SUCCESS: Domain is using Managed Login v2")
        else:
            logger.warning(f"⚠️  WARNING: Domain has ManagedLoginVersion {version} (expected 2)")
    except Exception as e:
        logger.error(f"❌ Failed to verify: {str(e)}")
        results['verification'] = f'failed: {str(e)}'

    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }
