'''data layer abstraction.'''
from time import time
import boto3
from sslnotifyme import (DOMAINNAME, BACKUP_BUCKET, lambda_main_wrapper)


class Backup(object):
    '''Backup object.'''
    def __init__(self, prefix=''):
        self._client = boto3.client('s3')
        self._prefix = prefix

    def persist(self, data):
        '''Persiste data to bucket object with current timestamp.'''
        import json
        key = '%s%d.json' % (
            self._prefix,
            int(time())) # we use UNIX epoch as filename

        self._client.put_object(
            ACL='private',
            Body=json.dumps(data),
            Bucket=BACKUP_BUCKET,
            Key=key,
        )
        return {'response': 's3://%s/%s' % (BACKUP_BUCKET, key)}


class DataStore(object):
    '''Data abstraction class.'''

    def __init__(self):
        '''Initialize object.'''
        self._client = boto3.client('dynamodb')
        self._tables = {
            'users': '%s_users' % DOMAINNAME.replace('.', ''),
            'pending': '%s_pending' % DOMAINNAME.replace('.', ''),
        }
        self._tables_keys = {
            'users': (('email', 'S'), ('domain', 'S'), ('days', 'N'), ('uuid', 'S')),
            'pending': (('email', 'S'), ('domain', 'S'), ('days', 'N'),
                        ('uuid', 'S'), ('ttl', 'N')),
        }

    def _get_all_records(self, table):
        '''Return users dict.'''
        records = self._client.scan(
            TableName=self._tables[table],
            Select='ALL_ATTRIBUTES',
        ).get('Items')
        result_set = []
        for record in records:
            result_set.append(self._parse_record(record, table))
        return result_set

    def _fetch_user(self, user, table):
        return self._client.get_item(
            TableName=self._tables[table],
            Key={'email': {'S': user}},
        ).get('Item')

    def _fetch_and_delete_user(self, user, table):
        response = self._client.delete_item(
            TableName=self._tables[table],
            Key={'email': {'S': user}},
            ReturnValues='ALL_OLD')
        return response.get('Attributes', {})

    def _put_user(self, user, domain, uuid, days, table):
        self._client.put_item(
            TableName=self._tables[table],
            Item={
                'email': {'S': user},
                'domain': {'S': domain},
                'uuid': {'S': uuid},
                'days': {'N': days},
            })

    def _parse_record(self, record, table):
        result = {}
        if record:
            for key_name, key_type in self._tables_keys[table]:
                if record.get(key_name):
                    result[key_name] = record[key_name].get(key_type)
        return result

    def _verify_user(self, user, uuid, table):
        '''Verify if uuid is matching user in table, return record if valid.'''
        parsed = self._parse_record(self._fetch_user(user, table), table)
        if parsed.get('uuid') and parsed['uuid'] == uuid:
            return parsed

    def get_validated_users(self):
        '''Return dict with validated users data.'''
        return {'response': self._get_all_records('users')}

    def get_pending_users(self):
        '''Return dict with pending users data.'''
        return {'response': self._get_all_records('pending')}

    def get_and_remove_pending_user(self, user):
        '''Fetch (if available) and remove user from 'pending' table.'''
        return {'response': self._parse_record(self._fetch_and_delete_user(user, 'pending'),
                                               'pending')}

    def put_user_to_pending(self, user, domain, days):
        '''Put record into 'pending' table, returns generated uniq id.'''
        from datetime import (datetime, timedelta)
        import uuid
        ttl = datetime.utcnow() + timedelta(days=2)
        uniq = uuid.uuid4().hex
        self._client.put_item(
            TableName=self._tables['pending'],
            Item={
                'email': {'S': user},
                'domain': {'S': domain},
                'uuid': {'S': uniq},
                'days': {'N': str(int(round(days)))},
                'ttl': {'N': ttl.strftime('%s')},
            })
        return {'response': 'user added successfully', 'uuid': uniq}

    def put_user_to_users(self, user, domain, days, uuid):
        '''Put user into users table.'''
        self._client.put_item(
            TableName=self._tables['users'],
            Item={
                'email': {'S': user},
                'domain': {'S': domain},
                'uuid': {'S': uuid},
                'days': {'N': str(int(round(days)))},
            })
        return {'response': 'user added successfully'}

    def validate_pending_user(self, user, uuid):
        '''Move user from pending to users table if uuid is valid, return True if found.'''
        record = self._verify_user(user, uuid, 'pending')
        if record:
            self._fetch_and_delete_user(user, 'pending')
            self._put_user(
                record['email'], record['domain'], record['uuid'], record['days'],
                'users')
            return {'response': 'user validation successful'}
        return {'errorMessage': 'user not found or wrong uuid'}

    def delete_validated_user(self, user, uuid):
        '''Delete user from valid users table if uuid is valid, return True if found.'''
        record = self._verify_user(user, uuid, 'users')
        if record:
            self._fetch_and_delete_user(user, 'users')
            return {'response': 'user deletion successful'}
        return {'errorMessage': 'user not found or wrong uuid'}

    def backup_tables(self):
        '''Store data as JSON into S3 BACKUP_BUCKET.'''
        return Backup('dynamodb-').persist({
            'users': self.get_validated_users()['response'],
            'pending': self.get_pending_users()['response'],
        })


# pylint: disable=unused-argument
def lambda_main(event, context):
    '''Lambda entry point.'''
    return lambda_main_wrapper(event, DataStore)
