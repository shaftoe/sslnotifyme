'''Py.test'''
import json
import sys
from moto import mock_dynamodb2, mock_s3
import boto3

sys.path.append('./lambda')
import data
from sslnotifyme import (APPNAME, BACKUP_BUCKET)


@mock_dynamodb2
def test_data_object():
    '''Test data abstraction layer.'''
    dyn = boto3.client('dynamodb')
    for table in ('pending', 'users'):
        dyn.create_table(
            TableName='%s_%s' % (APPNAME, table),
            AttributeDefinitions=[
                {'AttributeName':'email', 'AttributeType':'S'},
            ],
            KeySchema=[{'AttributeName':'email', 'KeyType':'S'}],
            ProvisionedThroughput={'ReadCapacityUnits':5, 'WriteCapacityUnits':5},
        )
    data_obj = data.DataStore()
    assert data_obj.get_validated_users() == {'response': []}
    assert data_obj.get_pending_users() == {'response': []}
    # TODO add put/delete tests when this is clarified:
    # https://github.com/spulec/moto/issues/873


@mock_s3
def test_backup_object():
    '''Test S3 backup.'''
    s3client = boto3.client('s3')
    s3client.create_bucket(Bucket=BACKUP_BUCKET)

    backup_obj = data.Backup('dynamodb-')
    mock_data = {'some': 'data'}
    file_url = backup_obj.persist(mock_data).get('response')
    file_name = file_url.split('/').pop()
    assert file_name.startswith('dynamodb-')

    content = s3client.get_object(
        Bucket=BACKUP_BUCKET,
        Key=file_name,
    ).get('Body').read()
    assert content == json.dumps(mock_data)
