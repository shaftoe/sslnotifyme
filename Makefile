SRCDIR = lambda
BUILDDIR = infra/build
FRONTENDDIR = frontend
OBJS = $(BUILDDIR)/checker.zip $(BUILDDIR)/cron.zip \
       $(BUILDDIR)/data.zip $(BUILDDIR)/mailer.zip \
       $(BUILDDIR)/reporter.zip

deploy: lambdas api frontend

apply:
	cd infra && terraform apply

plan:
	cd infra && terraform plan

lambdas: clean directories $(OBJS) apply

api:
	cd $(SRCDIR) && chalice deploy

cron:
	aws lambda invoke --function-name sslnotifyme_cron --invocation-type Event /dev/null

report:
	aws lambda invoke --function-name sslnotifyme_reporter --invocation-type Event /dev/null

frontend: frontend-tests
	cd $(FRONTENDDIR) && bash deploy.sh

frontend-tests:
	cd $(FRONTENDDIR) && html5validator && bootlint *.html

$(BUILDDIR)/checker.zip:
	cd $(SRCDIR) && zip -r ../$(BUILDDIR)/checker.zip checker.py sslnotifyme

$(BUILDDIR)/cron.zip:
	cd $(SRCDIR) && zip -r ../$(BUILDDIR)/cron.zip cron.py sslnotifyme

$(BUILDDIR)/data.zip:
	cd $(SRCDIR) && zip -r ../$(BUILDDIR)/data.zip data.py sslnotifyme

$(BUILDDIR)/mailer.zip:
	cd $(SRCDIR) && zip -r ../$(BUILDDIR)/mailer.zip mailer.py sslnotifyme

$(BUILDDIR)/reporter.zip:
	cd $(SRCDIR) && zip -r ../$(BUILDDIR)/reporter.zip reporter.py sslnotifyme

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

.PHONY : clean directories

directories: $(BUILDDIR)

clean:
	-rm -r $(BUILDDIR) $(SRCDIR)/sslnotifyme/__init__.pyc
