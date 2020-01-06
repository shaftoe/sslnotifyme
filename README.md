# --- DISCONTINUED ---

**This project has been discontinued (i.e. frontend and webservice backend are not online anymore), feel free to fork and/or register the same domains (sslnotify.me / sslexpired.info) if you're interested in maintaining it. Have fun!**

# sslnotify.me

[![Build Status](https://travis-ci.org/shaftoe/sslnotifyme.svg?branch=master)](https://travis-ci.org/shaftoe/sslnotifyme)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

Here you find the code behind [sslnotify.me](https://sslnotify.me/), a web service solution developed using serverless technologies. The service itself lives on top of [sslexpired.info](https://sslexpired.info/) (also serverless), which is developed with OpenWhisk and hosted by IBM Bluemix platform.

Beside a couple of services not fully manageble via APIs without human interaction, e.g. ACM and SES verifications, every other component of the application is deployed (and updated) using [Terraform](https://www.terraform.io/). NOTE: Terraform has to be applied in a two steps fashion because CloudFront initialization requires long time, hence breaking the Terraform model.

Those services/technologies has been used:

- [Chalice framework](http://chalice.readthedocs.io/) - to expose a simple REST API via AWS API Gateway
- Amazon Web Services:
    - Lambda (Python 2.7.10) - for almost everything else
    - DynamoDB (data persistency)
    - S3 (data backup)
    - SES (email notifications)
    - Route53 (DNS records)
    - CloudFront (delivery of frontend static files via https, redirect of http to https)
    - ACM (SSL certificate for both frontend and APIs)
    - CloudWatch Logs (logging and reporting)
- Bootstrap + jQuery (JS frontend)
- Moto and Py.test (unit tests, work in progress)

## DEPLOY: Setup AWS SES (Simple Email Service)

We use [SES](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/Welcome.html) to verify the user email and to notify the user when the SSL certificate is going to expire. These are the steps needed to enable SES:

    # To add a verified email for testing SES while developing:
    $ aws ses verify-email-identity --email-address testing@email

    # Following tokens needed by Terraform to setup the SES service
    $ aws ses verify-domain-identity --domain sslnotify.me
    {
        "VerificationToken": "ll+/A5/sVF..............7Y0Qmyd3E="
    }
    $ aws ses verify-domain-dkim --domain sslnotify.me
    {
        "DkimTokens": [
            "2mfjeqrrkc34..............i2wwnozfz5",
            "e5tcb5org5gw..............povm5o7rjk",
            "w5lpisumkfdf..............f3um27q7bz"
        ]
    }

NOTE: you'll have to write a ticket to AWS to be removed from the SES sandbox which allows you to send emails only to verified email addressed.

# DEPLOY: Setup main infrastructure with Terraform

In this step, we'll setup all the needed AWS infrastructure components, including the ones managed via Chalice (API Gateway and the _sslnotify_api_ lambda).

Copy `terraform.tfvars.template` into `terraform.tfvars` file and add missing vars (leave untouched only the ones referring to CloudFront for now):

    $ cp infra/terraform.tfvars.template infra/terraform.tfvars
    $ vim infra/terraform.tfvars # EDIT: aws_account_id, aws_region, dkim*_token, domain_name, ses_bounce_email and verification_token
    $ make apply
    cd infra && terraform apply
    [...]

At this point the infrastructure to deploy our lambda-api should be ready, we must configure it before deploying:

    # we need to configure chalice to use the right AWS account id
    $ sed 's/XXXXXXXX/<your 12 digits long AWS account ID>/g' lambda/.chalice/config.json.template > lambda/.chalice/config.json

    # let's deploy it
    $ make api
    cd lambda && chalice deploy
    [...]
    Updating IAM policy.
    Updating lambda function...
    Regen deployment package...
    Sending changes to lambda.
    Lambda deploy done.
    API Gateway rest API already found.
    Deleting root resource id
    Done deleting existing resources.
    Deploying to: dev
    https://3k3kkazz.execute-api.us-east-1.amazonaws.com/dev/

Take note of the _rest-api-id_, the first part of the url (you can always find it out later with `aws apigateway get-rest-apis`), because you'll have to add it to `terraform.tfvars` later on.

## Setup SSL certificate via AWS AMC for custom domain

- Create + validate the SSL certificate

        $ aws acm request-certificate --domain-name sslnotify.me --subject-alternative-names api.sslnotify.me
        {
            "CertificateArn": "arn:aws:acm:us-east-1:10000010000001:certificate/510713e7-0048-4f5a-be3f-edf8b20cd1de"
        }

    then check on the validation links sent via email by Amazon and take note of the identifier (510713e7-0048-4f5a-be3f-edf8b20cd1de)

- Enable cloudfront distrubution: https://console.aws.amazon.com/apigateway/home?region=us-east-1#/custom-domain-names. This will take up to 40 minutes to be active

- Copy *Distribution ID*, needed by Terraform (e.g. dawxiin7o72ic)

- Setup path mapping:

        $ aws apigateway create-base-path-mapping --domain-name api.sslnotify.me --rest-api-id 3k3kkazz --stage dev

- Set `aws_cloudfront_enabled` to true and `aws_cloudfront_id` in `terraform.tfvars`, then apply the changes:

        $ vim infra/terraform.tfvars

## DEPLOY All The Things!

    $ make

## APIs interaction

To add an user to the pending table (idempotent):

    $ curl -X PUT https://api.sslnotify.me/user/testing@email?domain=testme.com
    # this will send an email with a validation link to testing@email

To validate the user and add it to the users table, send a PUT with the uuid received via email, e.g.:

    $ curl -X PUT https://api.sslnotify.me/user/testing@email?uuid=797345a889e4424ab74d38939161855c

To delete the validated user:

    $ curl -X DELETE https://api.sslnotify.me/user/testing@email?uuid=797345a889e4424ab74d38939161855c

## Implementation

- API backend (_lambda/app.py_) developed using [Chalice framework](http://chalice.readthedocs.io/) to expose public REST commands
- Interface to persistency (based on AWS DynamoDB), including backups, in lambda _lambda/data.py_
- Email delivery based on Amazon SES in lambda _lambda/mailer.py_
- Check against [sslexpired.info](https://sslexpired.info/) APIs in lambda _lambda/checker.py_
- Daily cronjob lambda in _lambda/cron.py_
- Daily report of CloudWatch Logs in _lambda/reporter.py_
