# Generated by Django 3.0.6 on 2020-06-24 05:26

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("posthog", "0061_featureflag"),
    ]

    operations = [
        migrations.AddField(model_name="team", name="anonymize_ips", field=models.BooleanField(default=False),),
    ]