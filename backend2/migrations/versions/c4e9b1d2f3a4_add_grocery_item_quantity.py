"""add grocery_items.quantity

Revision ID: c4e9b1d2f3a4
Revises: a2c68d43b607
Create Date: 2026-04-14

"""
from alembic import op
import sqlalchemy as sa

revision = 'c4e9b1d2f3a4'
down_revision = 'a2c68d43b607'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'grocery_items',
        sa.Column(
            'quantity',
            sa.Integer(),
            server_default=sa.text('1'),
            nullable=False,
        ),
    )
    op.create_check_constraint(
        'grocery_items_quantity_check',
        'grocery_items',
        'quantity >= 1 AND quantity <= 10',
    )


def downgrade():
    op.drop_constraint('grocery_items_quantity_check', 'grocery_items', type_='check')
    op.drop_column('grocery_items', 'quantity')
