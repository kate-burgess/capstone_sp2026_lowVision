"""init

Revision ID: a2c68d43b607
Revises: 
Create Date: 2026-02-26 04:04:32.839878

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'a2c68d43b607'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    """
    Align the local database schema with the existing Supabase schema.

    This migration creates only the three application tables that already
    exist in Supabase:
      - grocery_items
      - grocery_lists
      - user_profiles

    It intentionally does NOT create any custom auth/user tables.
    """
    op.create_table(
        'grocery_items',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('list_id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), server_default=sa.text('auth.uid()'), nullable=True),
        sa.Column('name', sa.TEXT(), nullable=True),
        sa.Column('category', sa.TEXT(), nullable=True),
        sa.Column('is_checked', sa.BOOLEAN(), nullable=True),
        sa.ForeignKeyConstraint(
            ['list_id'],
            ['grocery_lists.id'],
            name='grocery_items_list_id_fkey',
            onupdate='CASCADE',
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id', name='grocery_items_pkey'),
    )

    op.create_table(
        'grocery_lists',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', sa.UUID(), server_default=sa.text('auth.uid()'), nullable=False),
        sa.Column('title', sa.TEXT(), nullable=True),
        sa.Column(
            'created_at',
            postgresql.TIMESTAMP(timezone=True),
            server_default=sa.text('now()'),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(
            ['user_id'],
            ['auth.users.id'],
            name='grocery_lists_user_id_fkey',
        ),
        sa.PrimaryKeyConstraint('id', name='grocery_lists_pkey'),
    )

    op.create_table(
        'user_profiles',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('full_name', sa.TEXT(), nullable=True),
        sa.Column('dietary_preferences', sa.TEXT(), nullable=True),
        sa.Column('allergies', sa.TEXT(), nullable=True),
        sa.ForeignKeyConstraint(
            ['id'],
            ['auth.users.id'],
            name='user_profiles_id_fkey',
        ),
        sa.PrimaryKeyConstraint('id', name='user_profiles_pkey'),
    )



def downgrade():
    """
    Drop the Supabase-aligned application tables.

    Note: This only affects the connected database when the migration is
    actually downgraded; it does not touch Supabase unless you run
    `flask db downgrade`.
    """
    op.drop_table('grocery_items')
    op.drop_table('grocery_lists')
    op.drop_table('user_profiles')
