from sqlmodel import SQLModel, Field


class PaymentBase(SQLModel):
    mode: str
    price: int
    status: str


class Payment(PaymentBase, table=True):
    id: int = Field(default=None, nullable=False, primary_key=True)


class PaymentCreate(PaymentBase):
    pass